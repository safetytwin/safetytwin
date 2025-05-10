#!/usr/bin/env python3
"""
Definicje tras API dla VM Bridge.
"""

import json
import logging
from flask import Blueprint, request, jsonify, current_app
from ..vm_bridge import VMBridge

# Konfiguracja logowania
logger = logging.getLogger("vm-bridge.api.routes")

# Utworzenie blueprintu
main_bp = Blueprint('main', __name__)

# Instancja VMBridge
vm_bridge = None

@main_bp.before_app_first_request
def initialize_vm_bridge():
    """Inicjalizuje VMBridge przed pierwszym żądaniem"""
    global vm_bridge
    try:
        vm_name = current_app.config.get('VM_NAME')
        config_path = current_app.config.get('VM_BRIDGE_CONFIG')
        vm_bridge = VMBridge(vm_name, config_path)
        logger.info(f"Zainicjalizowano VMBridge dla VM: {vm_name}")
    except Exception as e:
        logger.error(f"Błąd podczas inicjalizacji VMBridge: {e}")
        # Nie rzucamy wyjątku, aby aplikacja mogła się uruchomić
        # Kolejne żądania będą sprawdzać, czy vm_bridge jest None

@main_bp.route('/api/v1/update_state', methods=['POST'])
def update_state():
    """Endpoint API do odbierania aktualizacji stanu"""
    global vm_bridge
    
    # Sprawdź, czy VMBridge jest zainicjalizowany
    if vm_bridge is None:
        try:
            initialize_vm_bridge()
            if vm_bridge is None:
                return jsonify({
                    "status": "error", 
                    "message": "VMBridge nie został zainicjalizowany"
                }), 500
        except Exception as e:
            logger.error(f"Nie można zainicjalizować VMBridge: {e}")
            return jsonify({
                "status": "error", 
                "message": f"Błąd inicjalizacji VMBridge: {str(e)}"
            }), 500
    
    try:
        # Pobierz dane stanu z żądania
        state_data = request.json
        if not state_data:
            return jsonify({
                "status": "error", 
                "message": "Brak danych stanu"
            }), 400
            
        # Aktualizuj stan w VMBridge
        updated = vm_bridge.update_state(state_data)
        
        if updated:
            return jsonify({
                "status": "updated", 
                "snapshot": vm_bridge.current_snapshot
            })
        else:
            return jsonify({
                "status": "no_changes"
            })
            
    except Exception as e:
        logger.error(f"Błąd podczas aktualizacji stanu: {e}")
        return jsonify({
            "status": "error", 
            "message": str(e)
        }), 500

@main_bp.route('/api/v1/snapshots', methods=['GET'])
def list_snapshots():
    """Endpoint API do listowania snapshotów"""
    global vm_bridge
    
    # Sprawdź, czy VMBridge jest zainicjalizowany
    if vm_bridge is None:
        return jsonify({
            "status": "error", 
            "message": "VMBridge nie został zainicjalizowany"
        }), 500
    
    try:
        return jsonify({
            "current": vm_bridge.current_snapshot,
            "history": vm_bridge.snapshot_history
        })
    except Exception as e:
        logger.error(f"Błąd podczas listowania snapshotów: {e}")
        return jsonify({
            "status": "error", 
            "message": str(e)
        }), 500

@main_bp.route('/api/v1/snapshots/<string:name>', methods=['POST'])
def revert_snapshot(name):
    """Endpoint API do przywracania snapshotu"""
    global vm_bridge
    
    # Sprawdź, czy VMBridge jest zainicjalizowany
    if vm_bridge is None:
        return jsonify({
            "status": "error", 
            "message": "VMBridge nie został zainicjalizowany"
        }), 500
    
    try:
        success = vm_bridge.revert_to_snapshot(name)
        if success:
            return jsonify({
                "status": "reverted", 
                "snapshot": name
            })
        else:
            return jsonify({
                "status": "error", 
                "message": f"Nie udało się przywrócić snapshotu {name}"
            }), 400
    except Exception as e:
        logger.error(f"Błąd podczas przywracania snapshotu: {e}")
        return jsonify({
            "status": "error", 
            "message": str(e)
        }), 500

@main_bp.route('/api/v1/snapshots/<string:name>', methods=['DELETE'])
def delete_snapshot(name):
    """Endpoint API do usuwania snapshotu"""
    global vm_bridge
    
    # Sprawdź, czy VMBridge jest zainicjalizowany
    if vm_bridge is None:
        return jsonify({
            "status": "error", 
            "message": "VMBridge nie został zainicjalizowany"
        }), 500
    
    try:
        success = vm_bridge.delete_snapshot(name)
        if success:
            return jsonify({
                "status": "success", 
                "message": f"Usunięto snapshot {name}"
            })
        else:
            return jsonify({
                "status": "error", 
                "message": f"Nie udało się usunąć snapshotu {name}"
            }), 500
    except Exception as e:
        logger.error(f"Błąd podczas usuwania snapshotu: {e}")
        return jsonify({
            "status": "error", 
            "message": str(e)
        }), 500

@main_bp.route('/api/v1/status', methods=['GET'])
def get_status():
    """Endpoint API do sprawdzania statusu VM Bridge"""
    global vm_bridge
    
    if vm_bridge is None:
        return jsonify({
            "status": "not_initialized",
            "message": "VMBridge nie został jeszcze zainicjalizowany"
        })
    
    try:
        vm_ip = vm_bridge.get_vm_ip()
        vm_running = vm_ip is not None and vm_bridge.check_ssh_connection(vm_ip)
        
        return jsonify({
            "status": "ok",
            "vm_name": vm_bridge.vm_name,
            "vm_ip": vm_ip,
            "vm_running": vm_running,
            "current_snapshot": vm_bridge.current_snapshot,
            "snapshot_count": len(vm_bridge.snapshot_history)
        })
    except Exception as e:
        logger.error(f"Błąd podczas pobierania statusu: {e}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
