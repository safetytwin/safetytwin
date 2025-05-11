#!/usr/bin/env python3
"""
VM Bridge - Łącznik między systemem monitorującym a wirtualną maszyną.
Zarządza procesem tworzenia, aktualizacji i przełączania między snapshotami VM.
"""

import os
import time
import json
import logging
import subprocess
import shutil
import libvirt
import yaml
import threading
import paramiko
from datetime import datetime
from deepdiff import DeepDiff

# Konfiguracja logowania
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/tmp/vm-bridge.log')
    ]
)
logger = logging.getLogger("vm-bridge")

class VMBridge:
    """Klasa zarządzająca mostem między systemem monitorowanym a wirtualną maszyną"""
    
    def __init__(self, vm_name, config_path="/etc/vm-bridge.yaml"):
        """Inicjalizacja VMBridge"""
        self.vm_name = vm_name
        self.config_path = config_path
        self.current_state = {}
        self.current_snapshot = None
        self.snapshot_history = []
        self.max_snapshots = 10  # Maksymalna liczba przechowywanych snapshotów
        self.lock = threading.Lock()
        
        # Wczytaj konfigurację
        self.load_config()
        
        # Połącz z libvirt
        self.conn = libvirt.open(self.libvirt_uri)
        if self.conn is None:
            raise Exception(f"Nie można połączyć z hypervisorem: {self.libvirt_uri}")
            
        # Sprawdź, czy VM istnieje
        try:
            self.domain = self.conn.lookupByName(self.vm_name)
            logger.info(f"Znaleziono istniejącą VM: {self.vm_name}")
        except libvirt.libvirtError:
            logger.error(f"Nie można znaleźć VM: {self.vm_name}. Należy utworzyć bazową VM.")
            self.domain = None
            
    def load_config(self):
        """Wczytuje konfigurację z pliku YAML"""
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)
                
            self.libvirt_uri = config.get('libvirt_uri', 'qemu:///system')
            self.vm_user = config.get('vm_user', 'root')
            self.vm_password = config.get('vm_password', '')
            self.vm_key_path = config.get('vm_key_path', '~/.ssh/id_rsa')
            self.ansible_inventory = config.get('ansible_inventory', '/etc/vm-bridge/inventory.yml')
            self.ansible_playbook = config.get('ansible_playbook', '/etc/vm-bridge/apply_services.yml')
            self.state_dir = config.get('state_dir', '/var/lib/vm-bridge/states')
            self.max_snapshots = config.get('max_snapshots', 10)
            
            # Utwórz katalog stanów, jeśli nie istnieje
            os.makedirs(self.state_dir, exist_ok=True)
            
            logger.info("Załadowano konfigurację")
        except Exception as e:
            logger.error(f"Błąd podczas wczytywania konfiguracji: {e}")
            # Domyślne wartości
            self.libvirt_uri = 'qemu:///system'
            self.vm_user = 'root'
            self.vm_password = ''
            self.vm_key_path = '~/.ssh/id_rsa'
            self.ansible_inventory = '/etc/vm-bridge/inventory.yml'
            self.ansible_playbook = '/etc/vm-bridge/apply_services.yml'
            self.state_dir = '/var/lib/vm-bridge/states'
            
    def create_snapshot(self, name=None):
        """Tworzy nowy snapshot VM i zarządza limitami czasowymi oraz ilościowymi."""
        if self.domain is None:
            logger.error("Nie można utworzyć snapshotu - VM nie istnieje")
            return None
        try:
            # Wygeneruj nazwę snapshotu, jeśli nie podano
            if name is None:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                name = f"state_{timestamp}"

            # XML dla snapshotu
            snapshot_xml = f"""
            <domainsnapshot>
                <name>{name}</name>
            </domainsnapshot>
            """
            # Utwórz snapshot
            self.domain.snapshotCreateXML(snapshot_xml, 0)
            logger.info(f"Utworzono snapshot: {name}")
            self.snapshot_history.append(name)

            # --- NOWA LOGIKA: usuwanie snapshotów starszych niż 1h oraz limit 10 najnowszych ---
            import xml.etree.ElementTree as ET
            now = datetime.now().timestamp()  # Aktualny czas lokalny
            keep_snapshots = []
            for snap_name in list(self.snapshot_history):
                try:
                    snap = self.domain.snapshotLookupByName(snap_name)
                    xml = snap.getXMLDesc()
                    root = ET.fromstring(xml)
                    # Spróbuj znaleźć znacznik creationTime w metadanych
                    creation_time = None
                    for meta in root.findall("metadata"):
                        for elem in meta:
                            if elem.tag.endswith("creationTime"):
                                try:
                                    creation_time = int(elem.text)
                                except Exception:
                                    pass
                    # Jeśli nie ma creationTime, użyj czasu utworzenia pliku snapshotu (jeśli dostępny)
                    if not creation_time:
                        creation_time = now  # fallback: snapshot właśnie utworzony
                    age = now - creation_time
                    if age > 3600:
                        snap.delete()
                        self.snapshot_history.remove(snap_name)
                        logger.info(f"Usunięto snapshot starszy niż 1h: {snap_name}")
                    else:
                        keep_snapshots.append((snap_name, creation_time))
                except Exception as e:
                    logger.warning(f"Nie można sprawdzić/usunąć snapshotu {snap_name}: {e}")

            # Zachowaj tylko 10 najnowszych snapshotów (wg creation_time)
            keep_snapshots.sort(key=lambda x: x[1], reverse=True)
            for snap_name, _ in keep_snapshots[10:]:
                try:
                    snap = self.domain.snapshotLookupByName(snap_name)
                    snap.delete()
                    self.snapshot_history.remove(snap_name)
                    logger.info(f"Usunięto snapshot przekraczający limit 10: {snap_name}")
                except Exception as e:
                    logger.warning(f"Nie można usunąć snapshotu {snap_name}: {e}")

            # Odśwież listę snapshotów
            self.snapshot_history = [name for name, _ in keep_snapshots[:10] if name in self.snapshot_history]

            return name
        except libvirt.libvirtError as e:
            logger.error(f"Błąd podczas tworzenia snapshotu: {e}")
            return None
            
    def revert_to_snapshot(self, name):
        """Przywraca VM do stanu snapshotu"""
        if self.domain is None:
            logger.error("Nie można przywrócić snapshotu - VM nie istnieje")
            return False
            
        try:
            snapshot = self.domain.snapshotLookupByName(name)
            if self.domain.hasCurrentSnapshot():
                self.domain.revertToSnapshot(snapshot, 0)
                logger.info(f"Przywrócono VM do snapshotu: {name}")
                return True
            else:
                logger.error("VM nie ma aktualnego snapshotu")
                return False
        except libvirt.libvirtError as e:
            logger.error(f"Błąd podczas przywracania snapshotu: {e}")
            return False
            
    def wait_for_vm_boot(self, timeout=60):
        """Czeka, aż VM uruchomi się i będzie dostępna przez SSH"""
        start_time = time.time()
        vm_ip = self.get_vm_ip()
        
        if not vm_ip:
            logger.error("Nie można określić adresu IP VM")
            return False
            
        while time.time() - start_time < timeout:
            if self.check_ssh_connection(vm_ip):
                logger.info(f"VM jest dostępna pod adresem {vm_ip}")
                return True
            logger.info("Czekam na uruchomienie VM...")
            time.sleep(5)
            
        logger.error(f"Timeout podczas czekania na uruchomienie VM ({timeout}s)")
        return False
        
    def get_vm_ip(self):
        """Pobiera adres IP VM"""
        try:
            dom_xml = self.domain.XMLDesc(0)
            # Parsowanie XML do wydobycia MAC adresu
            # To jest uproszczona wersja - w rzeczywistości potrzebne jest dokładniejsze parsowanie
            import xml.etree.ElementTree as ET
            root = ET.fromstring(dom_xml)
            mac_addr = root.find(".//mac").get("address")
            
            # Wykonaj polecenie arp, aby znaleźć IP dla MAC
            result = subprocess.run(["arp", "-a"], capture_output=True, text=True)
            for line in result.stdout.splitlines():
                if mac_addr in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        return parts[1].strip("()")
            
            # Alternatywnie, możemy użyć virsh net-dhcp-leases
            result = subprocess.run(
                ["virsh", "net-dhcp-leases", "default"], 
                capture_output=True, 
                text=True
            )
            
            for line in result.stdout.splitlines():
                if mac_addr in line:
                    parts = line.split()
                    if len(parts) >= 5:
                        return parts[4].split('/')[0]
                        
            return None
        except Exception as e:
            logger.error(f"Błąd podczas pobierania IP VM: {e}")
            return None
            
    def check_ssh_connection(self, host, port=22, timeout=5):
        """Sprawdza, czy można połączyć się z VM przez SSH"""
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            key_path = os.path.expanduser(self.vm_key_path)
            
            if os.path.exists(key_path):
                key = paramiko.RSAKey.from_private_key_file(key_path)
                client.connect(
                    hostname=host,
                    port=port,
                    username=self.vm_user,
                    pkey=key,
                    timeout=timeout
                )
            else:
                client.connect(
                    hostname=host,
                    port=port,
                    username=self.vm_user,
                    password=self.vm_password,
                    timeout=timeout
                )
                
            client.close()
            return True
        except Exception as e:
            logger.debug(f"Nie można połączyć się z VM przez SSH: {e}")
            return False
            
    def apply_service_config(self, config_data):
        """Stosuje konfigurację usług do VM za pomocą Ansible"""
        try:
            # Zapisz konfigurację do pliku
            config_file = os.path.join(self.state_dir, "service_config.yaml")
            with open(config_file, 'w') as f:
                yaml.dump(config_data, f)
                
            # Przygotuj inwentarz Ansible
            vm_ip = self.get_vm_ip()
            if not vm_ip:
                logger.error("Nie można określić adresu IP VM")
                return False
                
            inventory = {
                "all": {
                    "hosts": {
                        "digital_twin": {
                            "ansible_host": vm_ip,
                            "ansible_user": self.vm_user
                        }
                    },
                    "vars": {
                        "ansible_ssh_private_key_file": os.path.expanduser(self.vm_key_path)
                    }
                }
            }
            
            # Zapisz inwentarz
            inventory_file = os.path.join(self.state_dir, "inventory.yaml")
            with open(inventory_file, 'w') as f:
                yaml.dump(inventory, f)
                
            # Uruchom Ansible
            ansible_cmd = [
                "ansible-playbook",
                "-i", inventory_file,
                self.ansible_playbook,
                "-e", f"config_file={config_file}"
            ]
            
            logger.info(f"Uruchamiam Ansible: {' '.join(ansible_cmd)}")
            result = subprocess.run(ansible_cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("Konfiguracja usług zastosowana pomyślnie")
                return True
            else:
                logger.error(f"Błąd podczas stosowania konfiguracji: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Błąd podczas stosowania konfiguracji usług: {e}")
            return False
            
    def update_state(self, new_state):
        """Aktualizuje stan VM na podstawie nowego stanu"""
        with self.lock:
            try:
                # Porównaj z bieżącym stanem
                if not self.current_state:
                    # Pierwszy stan - zapamiętaj i utwórz snapshot
                    logger.info("Pierwszy stan systemu - tworzę bazowy snapshot")
                    self.current_state = new_state
                    self.current_snapshot = self.create_snapshot("base_state")
                    return True
                    
                # Oblicz różnice
                diff = DeepDiff(self.current_state, new_state)
                
                # Jeśli są istotne różnice
                if diff:
                    logger.info(f"Wykryto zmiany w stanie: {len(diff)} różnic")
                    
                    # Zapisz nowy stan
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    state_file = os.path.join(self.state_dir, f"state_{timestamp}.json")
                    with open(state_file, 'w') as f:
                        json.dump(new_state, f, indent=2)
                        
                    # Utwórz snapshot przed zmianami
                    snapshot_name = f"state_{timestamp}"
                    self.create_snapshot(snapshot_name)
                    
                    # Wygeneruj konfigurację usług
                    service_config = self.generate_service_config(new_state)
                    
                    # Zastosuj konfigurację do VM
                    self.apply_service_config(service_config)
                    
                    # Zaktualizuj bieżący stan
                    self.current_state = new_state
                    self.current_snapshot = snapshot_name
                    
                    return True
                else:
                    logger.debug("Brak zmian w stanie")
                    return False
                    
            except Exception as e:
                logger.error(f"Błąd podczas aktualizacji stanu: {e}")
                return False
                
    def generate_service_config(self, state):
        """Generuje konfigurację usług na podstawie stanu systemu"""
        config = {
            "services": [],
            "processes": [],
            "system": {}
        }
        
        # Konfiguracja systemu
        if "hardware" in state:
            hw = state.get("hardware", {})
            config["system"] = {
                "hostname": hw.get("hostname", "digitaltwin"),
                "cpu": {
                    "count": hw.get("cpu", {}).get("logical_cores", 2),
                    "model": hw.get("cpu", {}).get("model", "unknown")
                },
                "memory": {
                    "total_gb": hw.get("memory", {}).get("total_gb", 4)
                },
                "kernel": hw.get("kernel_version", "unknown")
            }
        
        # Konfiguracja usług systemd
        if "services" in state:
            for service in state.get("services", []):
                if service.get("type") == "systemd":
                    systemd_service = {
                        "type": "systemd",
                        "name": service.get("name"),
                        "enabled": service.get("status") == "active",
                        "state": service.get("status", "stopped"),
                        "restart": "no"
                    }
                    
                    # Jeśli usługa ma PID, dodaj informacje o procesie
                    if service.get("pid"):
                        # Znajdź odpowiedni proces
                        for process in state.get("processes", []):
                            if process.get("pid") == service.get("pid"):
                                systemd_service["process"] = {
                                    "cmdline": process.get("cmdline", []),
                                    "env": process.get("environment", []),
                                    "cwd": process.get("cwd", "/")
                                }
                                break
                    
                    config["services"].append(systemd_service)
        
        # Konfiguracja kontenerów Docker
        if "services" in state:
            for service in state.get("services", []):
                if service.get("type") == "docker":
                    docker_service = {
                        "type": "docker",
                        "name": service.get("name"),
                        "image": service.get("image", ""),
                        "state": service.get("status", "stopped"),
                        "restart": service.get("restart_policy", "no"),
                        "ports": [],
                        "volumes": [],
                        "environment": service.get("environment", [])
                    }
                    
                    # Porty
                    for port in service.get("ports", []):
                        docker_service["ports"].append({
                            "container_port": port.get("container_port", ""),
                            "host_port": port.get("host_port", ""),
                            "host_ip": port.get("host_ip", "0.0.0.0")
                        })
                    
                    # Wolumeny
                    for volume in service.get("volumes", []):
                        docker_service["volumes"].append({
                            "source": volume.get("source", ""),
                            "destination": volume.get("destination", ""),
                            "read_only": volume.get("read_only", False)
                        })
                    
                    config["services"].append(docker_service)
        
        # Konfiguracja niezależnych procesów
        if "processes" in state:
            managed_pids = set()
            
            # Zbierz PIDs zarządzane przez usługi
            for service in state.get("services", []):
                if service.get("pid"):
                    managed_pids.add(service.get("pid"))
            
            # Dodaj niezarządzane procesy o wysokim użyciu CPU/pamięci
            for process in state.get("processes", []):
                if process.get("pid") not in managed_pids and process.get("cpu_percent", 0) > 1.0:
                    proc_config = {
                        "name": process.get("name", "unknown"),
                        "pid": process.get("pid"),
                        "user": process.get("username", "root"),
                        "cmdline": process.get("cmdline", []),
                        "cwd": process.get("cwd", "/"),
                        "cpu_percent": process.get("cpu_percent", 0),
                        "memory_percent": process.get("memory_percent", 0),
                        "environment": process.get("environment", [])
                    }
                    
                    # Dodaj informacje o limitach pamięci
                    if "memory_info" in process:
                        mem_info = process.get("memory_info", {})
                        proc_config["memory_limit_mb"] = int(mem_info.get("rss", 0) / (1024 * 1024) * 1.2)  # +20% margines
                    
                    config["processes"].append(proc_config)
        
        return config
    
    def list_snapshots(self):
        """Zwraca listę dostępnych snapshotów"""
        if self.domain is None:
            logger.error("Nie można listować snapshotów - VM nie istnieje")
            return {"current": None, "history": []}
            
        try:
            snapshots = self.domain.listAllSnapshots()
            snapshot_list = [snap.getName() for snap in snapshots]
            
            # Sprawdź aktualny snapshot
            current = None
            if self.domain.hasCurrentSnapshot():
                current = self.domain.snapshotCurrent().getName()
                
            return {
                "current": current,
                "history": snapshot_list
            }
        except libvirt.libvirtError as e:
            logger.error(f"Błąd podczas listowania snapshotów: {e}")
            return {"current": None, "history": []}
    
    def delete_snapshot(self, name):
        """Usuwa snapshot VM"""
        if self.domain is None:
            logger.error("Nie można usunąć snapshotu - VM nie istnieje")
            return False
            
        try:
            snapshot = self.domain.snapshotLookupByName(name)
            snapshot.delete()
            
            # Aktualizuj historię snapshotów
            if name in self.snapshot_history:
                self.snapshot_history.remove(name)
                
            logger.info(f"Usunięto snapshot: {name}")
            return True
        except libvirt.libvirtError as e:
            logger.error(f"Błąd podczas usuwania snapshotu: {e}")
            return False
    
    def save_state_to_file(self, state, filename=None):
        """Zapisuje stan do pliku"""
        try:
            if filename is None:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = f"state_{timestamp}.json"
                
            filepath = os.path.join(self.state_dir, filename)
            with open(filepath, 'w') as f:
                json.dump(state, f, indent=2)
                
            logger.info(f"Zapisano stan do pliku: {filepath}")
            return filepath
        except Exception as e:
            logger.error(f"Błąd podczas zapisywania stanu do pliku: {e}")
            return None
    
    def load_state_from_file(self, filename):
        """Wczytuje stan z pliku"""
        try:
            filepath = os.path.join(self.state_dir, filename)
            with open(filepath, 'r') as f:
                state = json.load(f)
                
            logger.info(f"Wczytano stan z pliku: {filepath}")
            return state
        except Exception as e:
            logger.error(f"Błąd podczas wczytywania stanu z pliku: {e}")
            return None

# Funkcja do uruchomienia VMBridge jako samodzielnego serwisu
def run_vm_bridge_service(config_path="/etc/vm-bridge.yaml"):
    """Uruchamia VMBridge jako serwis"""
    try:
        # Wczytaj konfigurację
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
            
        vm_name = config.get('vm_name', 'safetytwin')
        
        # Utwórz instancję VMBridge
        bridge = VMBridge(vm_name, config_path)
        
        # Tutaj można dodać logikę serwisu, np. serwer API Flask
        # lub nasłuchiwanie na zdarzenia
        
        logger.info(f"VMBridge uruchomiony dla VM: {vm_name}")
        
        # Przykładowa pętla główna
        while True:
            time.sleep(60)  # Czekaj na zdarzenia
            
    except Exception as e:
        logger.error(f"Błąd podczas uruchamiania serwisu VMBridge: {e}")
        return 1
        
    return 0

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="VM Bridge - Most między systemem monitorującym a wirtualną maszyną")
    parser.add_argument('--config', type=str, default='/etc/vm-bridge.yaml', help='Ścieżka do pliku konfiguracyjnego')
    args = parser.parse_args()
    
    sys.exit(run_vm_bridge_service(args.config))
