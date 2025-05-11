# Rozwiązywanie problemów

W tym dokumencie znajdziesz rozwiązania najczęstszych problemów, które mogą wystąpić podczas instalacji i używania systemu cyfrowego bliźniaka.

## Spis treści

1. [Problemy z instalacją](#problemy-z-instalacją)
2. [Problemy z agentem](#problemy-z-agentem)
3. [Problemy z VM Bridge](#problemy-z-vm-bridge)
4. [Problemy z maszyną wirtualną](#problemy-z-maszyną-wirtualną)
5. [Problemy z aktualizacją stanu](#problemy-z-aktualizacją-stanu)
6. [Problemy z wydajnością](#problemy-z-wydajnością)
7. [Problemy z API](#problemy-z-api)
8. [Jak zbierać logi diagnostyczne](#jak-zbierać-logi-diagnostyczne)

## Problemy z instalacją

### Błąd: "Libvirt nie jest zainstalowany"

**Problem**: Podczas instalacji pojawia się komunikat, że libvirt nie jest zainstalowany.

**Rozwiązanie**:
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y libvirt-clients libvirt-daemon-system qemu-kvm

# CentOS/RHEL
sudo yum install -y libvirt-client libvirt-daemon-system qemu-kvm

# Fedora
sudo dnf install -y libvirt-client libvirt-daemon-system qemu-kvm
```

### Błąd: "Nie można skompilować agenta"

**Problem**: Kompilacja agenta nie powodzi się.

**Rozwiązanie**:
1. Sprawdź, czy Go jest zainstalowane:
```bash
go version
```

2. Jeśli Go nie jest zainstalowane, zainstaluj je:
```bash
# Ubuntu/Debian
sudo apt-get install -y golang-go

# CentOS/RHEL
sudo yum install -y golang

# Fedora
sudo dnf install -y golang
```

3. Sprawdź, czy masz wszystkie zależności:
```bash
cd agent
go get -v ./...
```

4. Spróbuj ponownie skompilować:
```bash
go build -o digital-twin-agent main.go
```

### Błąd: "Nie można utworzyć maszyny wirtualnej"

**Problem**: Tworzenie maszyny wirtualnej nie powodzi się.

**Rozwiązanie**:
1. Sprawdź, czy wirtualizacja jest włączona w BIOS/UEFI.

2. Sprawdź, czy KVM jest dostępny:
```bash
ls -la /dev/kvm
```

3. Upewnij się, że Twój użytkownik należy do grupy `libvirt`:
```bash
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER
```

4. Zrestartuj usługę libvirt:
```bash
sudo systemctl restart libvirtd
```

5. Spróbuj ponownie utworzyć VM.

## Problemy z agentem

### Błąd: "Agent nie uruchamia się"

**Problem**: Usługa digital-twin-agent nie uruchamia się.

**Rozwiązanie**:
1. Sprawdź status usługi:
```bash
sudo systemctl status digital-twin-agent.service
```

2. Sprawdź logi:
```bash
sudo journalctl -u digital-twin-agent.service
```

3. Sprawdź, czy plik binarny agenta istnieje i ma uprawnienia do wykonania:
```bash
ls -la /opt/digital-twin/digital-twin-agent
```

4. Sprawdź, czy plik konfiguracyjny istnieje i jest poprawny:
```bash
cat /etc/digital-twin/agent-config.json
```

5. Spróbuj uruchomić agenta ręcznie, aby zobaczyć błędy:
```bash
sudo /opt/digital-twin/digital-twin-agent -config /etc/digital-twin/agent-config.json
```

### Błąd: "Agent nie może połączyć się z VM Bridge"

**Problem**: Agent nie może połączyć się z VM Bridge.

**Rozwiązanie**:
1. Sprawdź, czy adres IP i port VM Bridge są poprawne w konfiguracji agenta:
```bash
cat /etc/digital-twin/agent-config.json
```

2. Sprawdź, czy VM jest uruchomiona i dostępna w sieci:
```bash
ping $(virsh domifaddr digital-twin-vm | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
```

3. Sprawdź, czy port VM Bridge jest otwarty na VM:
```bash
sudo netstat -tulpn | grep 5678
```

4. Sprawdź, czy VM Bridge jest uruchomiony na VM:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "systemctl status digital-twin-bridge"
```

5. Sprawdź, czy firewall nie blokuje połączenia:
```bash
# Ubuntu/Debian
sudo ufw status

# CentOS/RHEL/Fedora
sudo firewall-cmd --list-all
```

### Błąd: "Agent zgłasza błędy w logach"

**Problem**: Agent zapisuje błędy w logach.

**Rozwiązanie**:
1. Sprawdź logi agenta:
```bash
sudo tail -f /var/log/digital-twin/agent.log
```

2. Włącz tryb verbose w konfiguracji agenta:
```bash
sudo sed -i 's/"verbose": false/"verbose": true/' /etc/digital-twin/agent-config.json
sudo systemctl restart digital-twin-agent.service
```

3. Zbierz bardziej szczegółowe logi i przeanalizuj błędy.

## Problemy z VM Bridge

### Błąd: "VM Bridge nie uruchamia się"

**Problem**: Usługa digital-twin-bridge nie uruchamia się.

**Rozwiązanie**:
1. Sprawdź status usługi:
```bash
sudo systemctl status digital-twin-bridge.service
```

2. Sprawdź logi:
```bash
sudo journalctl -u digital-twin-bridge.service
```

3. Sprawdź, czy skrypt VM Bridge istnieje i ma uprawnienia do wykonania:
```bash
ls -la /opt/digital-twin/vm_bridge.py
```

4. Sprawdź, czy plik konfiguracyjny istnieje i jest poprawny:
```bash
cat /etc/digital-twin/vm-bridge.yaml
```

5. Sprawdź, czy wszystkie zależności Python są zainstalowane:
```bash
pip3 list | grep -E 'flask|deepdiff|paramiko|libvirt|pyyaml|jinja2'
```

6. Spróbuj uruchomić VM Bridge ręcznie, aby zobaczyć błędy:
```bash
sudo /opt/digital-twin/vm_bridge.py --config /etc/digital-twin/vm-bridge.yaml --port 5678
```

### Błąd: "VM Bridge nie może połączyć się z libvirt"

**Problem**: VM Bridge nie może połączyć się z libvirt lub nie może zarządzać VM.

**Rozwiązanie**:
1. Sprawdź, czy libvirt działa:
```bash
sudo systemctl status libvirtd
```

2. Sprawdź, czy użytkownik running VM Bridge ma uprawnienia do libvirt:
```bash
sudo usermod -aG libvirt root
sudo usermod -aG kvm root
```

3. Zrestartuj libvirt:
```bash
sudo systemctl restart libvirtd
```

4. Sprawdź, czy URI libvirt w konfiguracji VM Bridge jest poprawny:
```bash
cat /etc/digital-twin/vm-bridge.yaml
```

### Błąd: "VM Bridge nie może zastosować konfiguracji do VM"

**Problem**: VM Bridge nie może zastosować konfiguracji do VM za pomocą Ansible.

**Rozwiązanie**:
1. Sprawdź, czy Ansible jest zainstalowany:
```bash
ansible --version
```

2. Sprawdź, czy plik inventory Ansible istnieje i jest poprawny:
```bash
cat /etc/digital-twin/inventory.yml
```

3. Sprawdź, czy VM jest dostępna przez SSH:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP
```

4. Sprawdź, czy playbook Ansible istnieje i jest poprawny:
```bash
cat /opt/digital-twin/apply_services.yml
```

5. Uruchom Ansible ręcznie, aby zobaczyć błędy:
```bash
ansible-playbook -i /etc/digital-twin/inventory.yml /opt/digital-twin/apply_services.yml -vvv
```

## Problemy z maszyną wirtualną

### Błąd: "VM nie uruchamia się"

**Problem**: Maszyna wirtualna nie uruchamia się.

**Rozwiązanie**:
1. Sprawdź status VM:
```bash
sudo virsh dominfo digital-twin-vm
```

2. Sprawdź logi VM:
```bash
sudo virsh log digital-twin-vm
```

3. Sprawdź logi QEMU:
```bash
sudo tail -f /var/log/libvirt/qemu/digital-twin-vm.log
```

4. Sprawdź, czy obraz dysku VM istnieje:
```bash
ls -la /var/lib/digital-twin/images/vm.qcow2
```

5. Sprawdź, czy VM ma wystarczające zasoby:
```bash
sudo virsh dumpxml digital-twin-vm | grep -E 'memory|vcpu'
```

### Błąd: "Nie można połączyć się z VM przez SSH"

**Problem**: Nie można połączyć się z maszyną wirtualną przez SSH.

**Rozwiązanie**:
1. Sprawdź, czy VM jest uruchomiona:
```bash
sudo virsh domstate digital-twin-vm
```

2. Sprawdź adres IP VM:
```bash
sudo virsh domifaddr digital-twin-vm
```

3. Sprawdź, czy VM jest dostępna w sieci:
```bash
ping $(sudo virsh domifaddr digital-twin-vm | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
```

4. Sprawdź, czy klucz SSH jest poprawny:
```bash
ls -la /etc/digital-twin/ssh/id_rsa
```

5. Spróbuj połączyć się z VM z opcją verbose:
```bash
ssh -vvv -i /etc/digital-twin/ssh/id_rsa root@VM_IP
```

6. Sprawdź, czy serwer SSH działa na VM:
```bash
sudo virsh console digital-twin-vm
# Zaloguj się i sprawdź
systemctl status sshd
```

### Błąd: "VM nie ma dostępu do internetu"

**Problem**: Maszyna wirtualna nie ma dostępu do internetu.

**Rozwiązanie**:
1. Sprawdź, czy sieć default w libvirt jest aktywna:
```bash
sudo virsh net-list --all
```

2. Sprawdź, czy sieć default ma włączone przekazywanie:
```bash
sudo virsh net-dumpxml default | grep -E 'forward|nat'
```

3. Sprawdź, czy VM ma interfejs sieciowy:
```bash
sudo virsh domiflist digital-twin-vm
```

4. Sprawdź konfigurację sieci na VM:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "ip addr"
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "ip route"
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "cat /etc/resolv.conf"
```

5. Sprawdź, czy maskarada jest włączona na hoście:
```bash
sudo iptables -t nat -L -v | grep MASQUERADE
```

## Problemy z aktualizacją stanu

### Błąd: "VM Bridge nie wykrywa zmian"

**Problem**: VM Bridge nie wykrywa zmian w stanie systemu.

**Rozwiązanie**:
1. Sprawdź, czy agent wysyła dane:
```bash
sudo tail -f /var/log/digital-twin/agent.log
```

2. Sprawdź, czy VM Bridge odbiera dane:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "journalctl -fu digital-twin-bridge"
```

3. Sprawdź, czy funkcja porównywania stanów działa poprawnie:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "cat /var/lib/digital-twin/states/state_latest.json"
```

4. Wprowadź znaczącą zmianę w systemie (np. uruchom nowy kontener Docker) i sprawdź, czy zostanie wykryta.

### Błąd: "Ansible nie może zastosować zmian"

**Problem**: Ansible nie może zastosować zmian do maszyny wirtualnej.

**Rozwiązanie**:
1. Sprawdź logi Ansible:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "cat /var/log/ansible.log"
```

2. Sprawdź, czy szablony Ansible istnieją:
```bash
ls -la /etc/digital-twin/templates/
```

3. Sprawdź, czy playbook Ansible jest poprawny:
```bash
ansible-playbook --syntax-check -i /etc/digital-twin/inventory.yml /opt/digital-twin/apply_services.yml
```

4. Uruchom Ansible ręcznie z opcją verbose:
```bash
ansible-playbook -i /etc/digital-twin/inventory.yml /opt/digital-twin/apply_services.yml -vvv
```

## Problemy z wydajnością

### Problem: "Agent zużywa zbyt dużo zasobów"

**Problem**: Agent zużywa zbyt dużo CPU lub pamięci.

**Rozwiązanie**:
1. Wyłącz zbieranie danych o procesach, jeśli nie jest potrzebne:
```bash
sudo sed -i 's/"include_processes": true/"include_processes": false/' /etc/digital-twin/agent-config.json
```

2. Wyłącz zbieranie danych o sieci, jeśli nie jest potrzebne:
```bash
sudo sed -i 's/"include_network": true/"include_network": false/' /etc/digital-twin/agent-config.json
```

3. Zwiększ interwał zbierania danych:
```bash
sudo sed -i 's/"interval": 10/"interval": 30/' /etc/digital-twin/agent-config.json
```

4. Zrestartuj agenta:
```bash
sudo systemctl restart digital-twin-agent.service
```

### Problem: "VM zużywa zbyt dużo zasobów"

**Problem**: Maszyna wirtualna zużywa zbyt dużo CPU lub pamięci.

**Rozwiązanie**:
1. Ograniczy ilość pamięci przydzielonej do VM:
```bash
sudo virsh setmaxmem digital-twin-vm 2G --config
sudo virsh setmem digital-twin-vm 2G --config
```

2. Ograniczy liczbę vCPU przydzielonych do VM:
```bash
sudo virsh setvcpus digital-twin-vm 1 --config
```

3. Zrestartuj VM:
```bash
sudo virsh shutdown digital-twin-vm
sudo virsh start digital-twin-vm
```

4. Ogranicz wykorzystanie zasobów przez usługi na VM:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "systemctl stop docker"
```

### Problem: "Snapshoty zajmują zbyt dużo miejsca"

**Problem**: Snapshoty maszyny wirtualnej zajmują zbyt dużo miejsca na dysku.

**Rozwiązanie**:
1. Ogranicz maksymalną liczbę przechowywanych snapshotów:
```bash
sudo sed -i 's/max_snapshots:.*/max_snapshots: 5/' /etc/digital-twin/vm-bridge.yaml
```

2. Usuń ręcznie stare snapshoty:
```bash
# Listuj snapshoty
sudo virsh snapshot-list digital-twin-vm

# Usuń snapshot
sudo virsh snapshot-delete digital-twin-vm --snapshotname STATE_NAME
```

3. Zrestartuj VM Bridge:
```bash
sudo systemctl restart digital-twin-bridge.service
```

## Problemy z API

### Błąd: "API nie odpowiada"

**Problem**: API VM Bridge nie odpowiada na żądania.

**Rozwiązanie**:
1. Sprawdź, czy VM Bridge działa:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "systemctl status digital-twin-bridge"
```

2. Sprawdź, czy port API jest otwarty:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "netstat -tulpn | grep 5678"
```

3. Sprawdź, czy API jest dostępne z hosta:
```bash
curl http://VM_IP:5678/api/v1/status
```

4. Sprawdź logi VM Bridge:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "journalctl -fu digital-twin-bridge"
```

5. Zrestartuj VM Bridge:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "systemctl restart digital-twin-bridge"
```

### Błąd: "Nie można przywrócić snapshotu"

**Problem**: Nie można przywrócić snapshotu poprzez API.

**Rozwiązanie**:
1. Sprawdź, czy snapshot istnieje:
```bash
sudo virsh snapshot-list digital-twin-vm
```

2. Sprawdź, czy nazwa snapshotu jest poprawna:
```bash
curl http://VM_IP:5678/api/v1/snapshots
```

3. Spróbuj przywrócić snapshot ręcznie:
```bash
sudo virsh snapshot-revert digital-twin-vm --snapshotname STATE_NAME
```

4. Sprawdź logi VM Bridge:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "journalctl -fu digital-twin-bridge"
```

## Jak zbierać logi diagnostyczne

Jeśli potrzebujesz pomocy w rozwiązaniu problemu, zbierz następujące logi diagnostyczne:

1. Logi agenta:
```bash
sudo cp /var/log/digital-twin/agent.log ~/agent.log
```

2. Logi VM Bridge:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "journalctl -u digital-twin-bridge -n 1000" > ~/vm-bridge.log
```

3. Logi systemd:
```bash
sudo journalctl -u digital-twin-agent -n 1000 > ~/agent-systemd.log
sudo journalctl -u libvirtd -n 1000 > ~/libvirtd.log
```

4. Logi VM:
```bash
sudo virsh dumpxml digital-twin-vm > ~/vm-config.xml
sudo virsh snapshot-list --domain digital-twin-vm > ~/vm-snapshots.txt
sudo cp /var/log/libvirt/qemu/digital-twin-vm.log ~/vm.log
```

5. Konfiguracja:
```bash
sudo cp /etc/digital-twin/agent-config.json ~/agent-config.json
sudo cp /etc/digital-twin/vm-bridge.yaml ~/vm-bridge.yaml
sudo cp /etc/digital-twin/inventory.yml ~/inventory.yml
```

6. Stan systemu:
```bash
sudo cp /var/lib/digital-twin/agent-states/state_latest.json ~/state.json
```

Spakuj wszystkie pliki i dołącz je do zgłoszenia problemu:

```bash
tar -czf digital-twin-logs.tar.gz ~/agent.log ~/vm-bridge.log ~/agent-systemd.log ~/libvirtd.log ~/vm-config.xml ~/vm-snapshots.txt ~/vm.log ~/agent-config.json ~/vm-bridge.yaml ~/inventory.yml ~/state.json
```