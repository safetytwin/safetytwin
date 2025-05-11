#!/usr/bin/env python3
"""
Skrypt uruchamiający aplikację Flask dla VM Bridge.
"""

import os
import argparse
import logging
from logging.handlers import RotatingFileHandler
from api.app import create_app

# Konfiguracja logowania
def setup_logging(log_level, log_file=None):
    """Konfiguruje system logowania"""
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    
    # Ustawienie poziomu logowania
    level = getattr(logging, log_level.upper())
    
    # Konfiguracja loggera głównego
    logger = logging.getLogger()
    logger.setLevel(level)
    
    # Handler dla konsoli
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(logging.Formatter(log_format))
    logger.addHandler(console_handler)
    
    # Handler dla pliku, jeśli podano
    if log_file:
        file_handler = RotatingFileHandler(
            log_file, maxBytes=10485760, backupCount=5
        )
        file_handler.setFormatter(logging.Formatter(log_format))
        logger.addHandler(file_handler)
    
    return logger

def parse_args():
    """Parsuje argumenty wiersza poleceń"""
    parser = argparse.ArgumentParser(description='VM Bridge API Server')
    
    parser.add_argument(
        '--host', 
        default='0.0.0.0', 
        help='Host do nasłuchiwania (domyślnie: 0.0.0.0)'
    )
    
    parser.add_argument(
        '--port', 
        type=int, 
        default=5678, 
        help='Port do nasłuchiwania (domyślnie: 5678)'
    )
    
    parser.add_argument(
        '--vm-name', 
        default=os.environ.get('VM_NAME', 'safetytwin'),
        help='Nazwa maszyny wirtualnej (domyślnie: safetytwin)'
    )
    
    parser.add_argument(
        '--config', 
        default=os.environ.get('VM_BRIDGE_CONFIG', '/etc/vm-bridge.yaml'),
        help='Ścieżka do pliku konfiguracyjnego (domyślnie: /etc/vm-bridge.yaml)'
    )
    
    parser.add_argument(
        '--debug', 
        action='store_true', 
        help='Uruchom w trybie debug'
    )
    
    parser.add_argument(
        '--log-level', 
        choices=['debug', 'info', 'warning', 'error', 'critical'],
        default='info',
        help='Poziom logowania (domyślnie: info)'
    )
    
    parser.add_argument(
        '--log-file', 
        help='Ścieżka do pliku logów (domyślnie: brak)'
    )
    
    return parser.parse_args()

def main():
    """Funkcja główna"""
    args = parse_args()
    
    # Konfiguracja logowania
    logger = setup_logging(args.log_level, args.log_file)
    
    # Konfiguracja aplikacji
    app_config = {
        'VM_NAME': args.vm_name,
        'VM_BRIDGE_CONFIG': args.config,
        'DEBUG': args.debug
    }
    
    # Utworzenie aplikacji
    app = create_app(app_config)
    
    # Uruchomienie serwera
    logger.info(f"Uruchamianie VM Bridge API na {args.host}:{args.port}")
    app.run(host=args.host, port=args.port, debug=args.debug)

if __name__ == '__main__':
    main()
