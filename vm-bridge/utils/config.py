#!/usr/bin/env python3
# vm-bridge/utils/config.py
"""
Moduł do zarządzania konfiguracją VM Bridge.
"""

import os
import yaml
import logging

logger = logging.getLogger("vm-bridge.config")


class Config:
    """Klasa zarządzająca konfiguracją VM Bridge."""

    def __init__(self, config_path):
        """Inicjalizacja konfiguracji z pliku YAML."""
        self.config_path = config_path

        # Wartości domyślne
        self.vm_name = "digital-twin-vm"
        self.libvirt_uri = "qemu:///system"
        self.vm_user = "root"
        self.vm_password = ""
        self.vm_key_path = "~/.ssh/id_rsa"
        self.ansible_inventory = "/etc/vm-bridge/inventory.yml"
        self.ansible_playbook = "/etc/vm-bridge/apply_services.yml"
        self.state_dir = "/var/lib/vm-bridge/states"
        self.templates_dir = "/etc/vm-bridge/templates"
        self.max_snapshots = 10

        # Wczytaj konfigurację z pliku
        self._load_config()

    def _load_config(self):
        """Wczytuje konfigurację z pliku YAML."""
        try:
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r') as f:
                    config = yaml.safe_load(f)

                if config:
                    # Aktualizuj wartości z pliku
                    self.vm_name = config.get('vm_name', self.vm_name)
                    self.libvirt_uri = config.get('libvirt_uri', self.libvirt_uri)
                    self.vm_user = config.get('vm_user', self.vm_user)
                    self.vm_password = config.get('vm_password', self.vm_password)
                    self.vm_key_path = config.get('vm_key_path', self.vm_key_path)
                    self.ansible_inventory = config.get('ansible_inventory', self.ansible_inventory)
                    self.ansible_playbook = config.get('ansible_playbook', self.ansible_playbook)
                    self.state_dir = config.get('state_dir', self.state_dir)
                    self.templates_dir = config.get('templates_dir', self.templates_dir)
                    self.max_snapshots = config.get('max_snapshots', self.max_snapshots)

                    logger.info(f"Wczytano konfigurację z {self.config_path}")
            else:
                logger.warning(f"Plik konfiguracyjny {self.config_path} nie istnieje, używam wartości domyślnych")

            # Przekształć ścieżki
            self.vm_key_path = os.path.expanduser(self.vm_key_path)

            # Utwórz katalogi, jeśli nie istnieją
            os.makedirs(self.state_dir, exist_ok=True)
            os.makedirs(os.path.dirname(self.ansible_inventory), exist_ok=True)

        except Exception as e:
            logger.error(f"Błąd podczas wczytywania konfiguracji: {e}")
            logger.warning("Używam wartości domyślnych")

    def save(self):
        """Zapisuje konfigurację do pliku."""
        try:
            config = {
                'vm_name': self.vm_name,
                'libvirt_uri': self.libvirt_uri,
                'vm_user': self.vm_user,
                'vm_password': self.vm_password,
                'vm_key_path': self.vm_key_path,
                'ansible_inventory': self.ansible_inventory,
                'ansible_playbook': self.ansible_playbook,
                'state_dir': self.state_dir,
                'templates_dir': self.templates_dir,
                'max_snapshots': self.max_snapshots
            }

            # Utwórz katalog, jeśli nie istnieje
            os.makedirs(os.path.dirname(self.config_path), exist_ok=True)

            with open(self.config_path, 'w') as f:
                yaml.dump(config, f, default_flow_style=False)

            logger.info(f"Zapisano konfigurację do {self.config_path}")
            return True
        except Exception as e:
            logger.error(f"Błąd podczas zapisywania konfiguracji: {e}")
            return False



