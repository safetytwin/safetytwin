#!/usr/bin/env python3
"""
Aplikacja Flask do odbierania danych z agenta i zarządzania VM.
"""

import os
import logging
from flask import Flask, jsonify
from flask_cors import CORS

# Konfiguracja logowania
logger = logging.getLogger("vm-bridge.api")

def create_app(config=None):
    """Tworzy i konfiguruje aplikację Flask"""
    app = Flask(__name__)
    
    # Konfiguracja CORS
    CORS(app)
    
    # Konfiguracja domyślna
    app.config.update(
        SECRET_KEY=os.environ.get('SECRET_KEY', 'dev_key_change_in_production'),
        VM_BRIDGE_CONFIG=os.environ.get('VM_BRIDGE_CONFIG', '/etc/vm-bridge.yaml'),
        VM_NAME=os.environ.get('VM_NAME', 'safetytwin'),
        DEBUG=os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    )
    
    # Nadpisz konfigurację, jeśli podano
    if config:
        app.config.update(config)
    
    # Zarejestruj blueprinty
    from .routes import main_bp
    app.register_blueprint(main_bp)
    
    # Obsługa błędów
    @app.errorhandler(404)
    def not_found(error):
        return jsonify({"status": "error", "message": "Nie znaleziono zasobu"}), 404
    
    @app.errorhandler(500)
    def server_error(error):
        logger.error(f"Błąd serwera: {error}")
        return jsonify({"status": "error", "message": "Błąd wewnętrzny serwera"}), 500
    
    return app
