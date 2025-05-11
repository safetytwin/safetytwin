#!/usr/bin/env python3
"""
VM Bridge - Most między systemem monitorującym a wirtualną maszyną.
Zarządza procesem tworzenia, aktualizacji i przełączania między snapshotami VM.
"""

import os
import sys
import time
import json
import yaml
import logging
import argparse
import threading
from datetime import datetime
from flask import Flask, request, jsonify, Response

# Import modułów własnych
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vm_bridge.utils.config import Config
from vm_bridge.utils.state_store import StateStore
from vm_bridge.utils.vm_manager import VMManager
from vm_bridge.utils.service_generator import ServiceGenerator

# Informacje o wersji
__version__ = '1.0.0'
__author__ = 'Digital Twin System'

# Konfiguracja logowania
def setup_logging(log_file='/var/log/digital-twin/vm-bridge.log', verbose=False):
    """Konfiguracja systemu logowania."""
    # Utwórz katalog logów, jeśli nie istnieje
    log_dir = os.path.dirname(log_file)
    os.makedirs(log_dir, exist_ok=True)
    
    # Konfiguracja loggera
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(log_file)
        ]
    )
    return logging.getLogger("vm-bridge")

# Zmienne globalne
logger = None
config = None
state_store = None
vm_manager = None
service_generator = None
lock = threading.Lock()

# Inicjalizacja aplikacji Flask
app = Flask(__name__)

@app.route('/api/v1/update_state', methods=['POST'])
def update_state():
    """Endpoint API do odbierania aktualizacji stanu."""
    with lock:
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
                logger.info(f"Wykryto zmiany w stanie systemu: {len(diff.keys() if isinstance(diff, dict) else diff)} różnic")
                
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

@app.route('/api/v1/snapshots', methods=['GET'])
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

@app.route('/api/v1/snapshots/<name>', methods=['POST'])
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

@app.route('/api/v1/status', methods=['GET'])
def get_status():
    """Endpoint API do sprawdzania statusu systemu."""
    try:
        vm_status = "unknown"
        if vm_manager and vm_manager.domain:
            vm_status = "running" if vm_manager.domain.isActive() else "stopped"
            
        uptime = int(time.time() - app.start_time)
        
        return jsonify({
            "status": "running",
            "vm_status": vm_status,
            "current_snapshot": vm_manager.current_snapshot,
            "api_version": "1.0",
            "uptime": uptime
        })
    except Exception as e:
        logger.error(f"Błąd podczas pobierania statusu: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/v1/history', methods=['GET'])
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
        </div>
    </body>
    </html>
    """
    return Response(html, mimetype='text/html')

def init_components(config_path):
    """Inicjalizacja komponentów systemu."""
    global config, state_store, vm_manager, service_generator, logger
    
    try:
        # Wczytaj konfigurację
        config = Config(config_path)
        
        # Inicjalizuj state store
        state_store = StateStore(config.state_dir)
        
        # Inicjalizuj VM manager
        vm_manager = VMManager(
            vm_name=config.vm_name,
            libvirt_uri=config.libvirt_uri,
            vm_user=config.vm_user,
            vm_key_path=config.vm_key_path,
            ansible_inventory=config.ansible_inventory,
            ansible_playbook=config.ansible_playbook
        )
        
        # Inicjalizuj generator usług
        service_generator = ServiceGenerator(config.templates_dir)
        
        logger.info("Komponenty zainicjalizowane pomyślnie")
        return True
    except Exception as e:
        logger.error(f"Błąd podczas inicjalizacji komponentów: {e}")
        return False

def main():
    """Główna funkcja programu."""
    global logger
    
    # Parsowanie argumentów wiersza poleceń
    parser = argparse.ArgumentParser(description='VM Bridge - Most między systemem monitorującym a wirtualną maszyną')
    parser.add_argument('--config', type=str, default='/etc/digital-twin/vm-bridge.yaml', 
                        help='Ścieżka do pliku konfiguracyjnego')
    parser.add_argument('--port', type=int, default=5678, 
                        help='Port na którym uruchomić API')
    parser.add_argument('--log', type=str, default='/var/log/digital-twin/vm-bridge.log',
                        help='Ścieżka do pliku logów')
    parser.add_argument('--verbose', action='store_true',
                        help='Tryb gadatliwy (więcej logów)')
    parser.add_argument('--version', action='store_true',
                        help='Wyświetl wersję i zakończ')
    args = parser.parse_args()
    
    # Wyświetl wersję i zakończ
    if args.version:
        print(f"VM Bridge v{__version__}")
        print(f"Copyright (c) 2025 {__author__}")
        return 0
    
    # Konfiguracja logowania
    logger = setup_logging(args.log, args.verbose)
    logger.info(f"VM Bridge v{__version__} uruchamianie...")
    
    # Inicjalizacja komponentów
    if not init_components(args.config):
        logger.error("Nie udało się zainicjalizować komponentów. Kończenie działania.")
        return 1
        
    # Dodaj zmienną czasu uruchomienia
    app.start_time = time.time()
    
    # Uruchom serwer API
    logger.info(f"Uruchamianie serwera API na porcie {args.port}...")
    app.run(host='0.0.0.0', port=args.port)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
