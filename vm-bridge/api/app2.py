#!/usr/bin/env python3
"""
Moduł API dla VM Bridge.
Udostępnia interfejs REST API do zarządzania VM Bridge.
"""

import os
import sys
import time
import logging
from datetime import datetime
from flask import Flask, request, jsonify, Response, Blueprint

# Dodaj katalog główny do ścieżki, aby można było importować moduły
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

# Informacje o wersji
__version__ = '1.0.0'

# Logger
logger = logging.getLogger("vm-bridge.api")

# Utworzenie blueprintu Flask
api_bp = Blueprint('api', __name__, url_prefix='/api/v1')

# Zmienne globalne
vm_manager = None
state_store = None
service_generator = None


def init_api(vm_mgr, state_str, service_gen):
    """Inicjalizacja API z komponentami VM Bridge."""
    global vm_manager, state_store, service_generator
    vm_manager = vm_mgr
    state_store = state_str
    service_generator = service_gen


@api_bp.route('/update_state', methods=['POST'])
def update_state():
    """Endpoint API do odbierania aktualizacji stanu."""
    try:
        # Pobierz dane stanu z żądania
        state_data = request.json
        if not state_data:
            return jsonify({"status": "error", "message": "Brak danych stanu"}), 400

        # Zapisz stan do state store
        state_id = state_store.save_state(state_data)

        # Porównaj z poprzednim stanem
        state_changed, diff = state_store.compare_with_previous(state_id)

        if state_changed:
            logger.info(
                f"Wykryto zmiany w stanie systemu: {len(diff.keys() if isinstance(diff, dict) else diff)} różnic")

            # Utwórz snapshot VM
            snapshot_name = f"state_{int(time.time())}"
            vm_manager.create_snapshot(snapshot_name)

            # Wygeneruj konfigurację usług
            service_config = service_generator.generate_service_config(state_data)

            # Zastosuj konfigurację do VM
            success = vm_manager.apply_service_config(service_config)

            if success:
                return jsonify({
                    "status": "updated",
                    "state_id": state_id,
                    "snapshot": snapshot_name,
                    "changes": diff
                })
            else:
                return jsonify({
                    "status": "error",
                    "message": "Nie udało się zastosować konfiguracji do VM"
                }), 500
        else:
            logger.info("Brak zmian w stanie systemu")
            return jsonify({"status": "no_changes", "state_id": state_id})

    except Exception as e:
        logger.error(f"Błąd podczas aktualizacji stanu: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/snapshots', methods=['GET'])
def list_snapshots():
    """Endpoint API do listowania snapshotów."""
    try:
        snapshots = vm_manager.list_snapshots()
        return jsonify({
            "status": "success",
            "snapshots": snapshots
        })
    except Exception as e:
        logger.error(f"Błąd podczas listowania snapshotów: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/snapshots/<name>', methods=['POST'])
def revert_snapshot(name):
    """Endpoint API do przywracania snapshotu."""
    try:
        success = vm_manager.revert_to_snapshot(name)
        if success:
            return jsonify({"status": "success", "message": f"Przywrócono snapshot {name}"})
        else:
            return jsonify({"status": "error", "message": f"Nie udało się przywrócić snapshotu {name}"}), 500
    except Exception as e:
        logger.error(f"Błąd podczas przywracania snapshotu: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/status', methods=['GET'])
def get_status():
    """Endpoint API do sprawdzania statusu systemu."""
    try:
        vm_status = "unknown"
        if vm_manager and vm_manager.domain:
            vm_status = "running" if vm_manager.domain.isActive() else "stopped"

        start_time = getattr(request.app, 'start_time', int(time.time()))
        uptime = int(time.time() - start_time)

        return jsonify({
            "status": "running",
            "vm_status": vm_status,
            "current_snapshot": vm_manager.current_snapshot,
            "api_version": __version__,
            "uptime": uptime
        })
    except Exception as e:
        logger.error(f"Błąd podczas pobierania statusu: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/history', methods=['GET'])
def get_history():
    """Endpoint API do pobierania historii stanów."""
    try:
        limit = request.args.get('limit', default=10, type=int)
        history = state_store.get_state_history(limit)
        return jsonify({
            "status": "success",
            "history": history
        })
    except Exception as e:
        logger.error(f"Błąd podczas pobierania historii: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/vm/start', methods=['POST'])
def start_vm():
    """Endpoint API do uruchamiania VM."""
    try:
        if not vm_manager or not vm_manager.domain:
            return jsonify({"status": "error", "message": "VM nie jest skonfigurowana"}), 500

        if vm_manager.domain.isActive():
            return jsonify({"status": "success", "message": "VM już jest uruchomiona"})

        vm_manager.domain.create()
        return jsonify({"status": "success", "message": "VM uruchomiona"})
    except Exception as e:
        logger.error(f"Błąd podczas uruchamiania VM: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/vm/stop', methods=['POST'])
def stop_vm():
    """Endpoint API do zatrzymywania VM."""
    try:
        if not vm_manager or not vm_manager.domain:
            return jsonify({"status": "error", "message": "VM nie jest skonfigurowana"}), 500

        if not vm_manager.domain.isActive():
            return jsonify({"status": "success", "message": "VM już jest zatrzymana"})

        vm_manager.domain.shutdown()
        return jsonify({"status": "success", "message": "VM zatrzymana"})
    except Exception as e:
        logger.error(f"Błąd podczas zatrzymywania VM: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/vm/restart', methods=['POST'])
def restart_vm():
    """Endpoint API do restartowania VM."""
    try:
        if not vm_manager or not vm_manager.domain:
            return jsonify({"status": "error", "message": "VM nie jest skonfigurowana"}), 500

        if not vm_manager.domain.isActive():
            vm_manager.domain.create()
            return jsonify({"status": "success", "message": "VM uruchomiona"})

        vm_manager.domain.reboot(0)
        return jsonify({"status": "success", "message": "VM zrestartowana"})
    except Exception as e:
        logger.error(f"Błąd podczas restartowania VM: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@api_bp.route('/vm/info', methods=['GET'])
def get_vm_info():
    """Endpoint API do pobierania informacji o VM."""
    try:
        if not vm_manager or not vm_manager.domain:
            return jsonify({"status": "error", "message": "VM nie jest skonfigurowana"}), 500

        # Pobierz informacje o VM
        vm_info = {
            "name": vm_manager.vm_name,
            "status": "running" if vm_manager.domain.isActive() else "stopped",
            "current_snapshot": vm_manager.current_snapshot,
            "ip_address": vm_manager.get_vm_ip() or "unknown"
        }

        # Dodaj informacje o sprzęcie, jeśli VM jest uruchomiona
        if vm_manager.domain.isActive():
            try:
                # Pobierz informacje o CPU
                vm_info["vcpus"] = vm_manager.domain.maxVcpus()

                # Pobierz informacje o pamięci
                vm_info["memory_kb"] = vm_manager.domain.maxMemory()
                vm_info["memory_gb"] = round(vm_info["memory_kb"] / (1024 * 1024), 2)

                # Pobierz informacje o dyskach
                vm_info["disks"] = []
                xml = vm_manager.domain.XMLDesc(0)
                import xml.etree.ElementTree as ET
                root = ET.fromstring(xml)
                for disk in root.findall(".//disk"):
                    if disk.get("device") == "disk":
                        source = disk.find("source")
                        target = disk.find("target")
                        if source is not None and target is not None:
                            vm_info["disks"].append({
                                "source": source.get("file"),
                                "target": target.get("dev")
                            })

                # Pobierz informacje o interfejsach sieciowych
                vm_info["interfaces"] = []
                for iface in root.findall(".//interface"):
                    if iface.get("type") == "network":
                        source = iface.find("source")
                        model = iface.find("model")
                        mac = iface.find("mac")
                        if source is not None:
                            interface_info = {
                                "network": source.get("network")
                            }
                            if model is not None:
                                interface_info["model"] = model.get("type")
                            if mac is not None:
                                interface_info["mac"] = mac.get("address")
                            vm_info["interfaces"].append(interface_info)
            except Exception as e:
                logger.warning(f"Nie można pobrać szczegółowych informacji o VM: {e}")

        return jsonify({
            "status": "success",
            "vm": vm_info
        })
    except Exception as e:
        logger.error(f"Błąd podczas pobierania informacji o VM: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


def create_app(vm_mgr, state_str, service_gen):
    """Tworzy i konfiguruje aplikację Flask z API."""
    app = Flask(__name__)
    app.start_time = time.time()

    # Inicjalizacja API
    init_api(vm_mgr, state_str, service_gen)

    # Rejestracja blueprintu
    app.register_blueprint(api_bp)

    # Strona główna
    @app.route('/', methods=['GET'])
    def root():
        """Strona główna API."""
        vm_status = "unknown"
        try:
            if vm_manager and vm_manager.domain:
                vm_status = "running" if vm_manager.domain.isActive() else "stopped"
        except:
            pass

        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Digital Twin VM Bridge</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }}
                h1 {{ color: #333; }}
                h2 {{ color: #444; margin-top: 20px; }}
                .status {{ padding: 10px; border-radius: 5px; margin: 20px 0; }}
                .running {{ background-color: #d4edda; color: #155724; }}
                .stopped {{ background-color: #f8d7da; color: #721c24; }}
                .unknown {{ background-color: #fff3cd; color: #856404; }}
                .endpoints {{ background-color: #e2e3e5; padding: 15px; border-radius: 5px; }}
                .endpoint {{ margin-bottom: 10px; }}
                .method {{ display: inline-block; width: 80px; font-weight: bold; }}
            </style>
        </head>
        <body>
            <h1>Digital Twin VM Bridge</h1>
            <p>Version: {__version__}</p>

            <div class="status {vm_status}">
                <strong>Status VM:</strong> {vm_status}
            </div>

            <h2>Dostępne Endpointy API:</h2>
            <div class="endpoints">
                <div class="endpoint"><span class="method">GET</span> /api/v1/status - Status systemu</div>
                <div class="endpoint"><span class="method">GET</span> /api/v1/snapshots - Lista snapshotów</div>
                <div class="endpoint"><span class="method">POST</span> /api/v1/snapshots/&lt;name&gt; - Przywróć snapshot</div>
                <div class="endpoint"><span class="method">GET</span> /api/v1/history - Historia stanów</div>
                <div class="endpoint"><span class="method">POST</span> /api/v1/update_state - Aktualizuj stan (dla agenta)</div>
                <div class="endpoint"><span class="method">GET</span> /api/v1/vm/info - Informacje o VM</div>
                <div class="endpoint"><span class="method">POST</span> /api/v1/vm/start - Uruchom VM</div>
                <div class="endpoint"><span class="method">POST</span> /api/v1/vm/stop - Zatrzymaj VM</div>
                <div class="endpoint"><span class="method">POST</span> /api/v1/vm/restart - Zrestartuj VM</div>
            </div>
        </body>
        </html>
        """
        return Response(html, mimetype='text/html')

    return app