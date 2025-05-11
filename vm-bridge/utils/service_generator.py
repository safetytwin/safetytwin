#!/usr/bin/env python3
"""
Moduł do generowania konfiguracji usług na podstawie danych systemowych.
"""

import os
import logging
import jinja2
import yaml
import json

logger = logging.getLogger("vm-bridge.service_generator")


class ServiceGenerator:
    """Klasa do generowania konfiguracji usług na podstawie danych systemowych."""

    def __init__(self, templates_dir):
        """Inicjalizacja generatora usług."""
        self.templates_dir = templates_dir

        # Tworzenie środowiska szablonów Jinja2
        self.jinja_env = jinja2.Environment(
            loader=jinja2.FileSystemLoader(templates_dir),
            trim_blocks=True,
            lstrip_blocks=True
        )

        # Sprawdź, czy katalog szablonów istnieje
        if not os.path.exists(templates_dir):
            os.makedirs(templates_dir)
            self._create_default_templates()

    def _create_default_templates(self):
        """Tworzy domyślne szablony, jeśli nie istnieją."""
        try:
            # Szablon dla skryptu uruchamiającego proces
            process_launcher_template = """#!/bin/bash
# Skrypt wygenerowany automatycznie przez system cyfrowego bliźniaka
# Proces: {{ item.name }} (PID: {{ item.pid }})
# Uruchomiony dla użytkownika: {{ item.user | default('root') }}

# Konfiguracja podstawowa
set -e

# Utworzenie katalogu roboczego
{% if item.cwd is defined %}
mkdir -p {{ item.cwd }}
cd {{ item.cwd }}
{% endif %}

# Ustawienie czasu początku
START_TIME=$(date +%s)
echo "Uruchamianie procesu {{ item.name }} - $(date)"

# Ustaw zmienne środowiskowe
{% if item.environment is defined %}
{% for env in item.environment %}
export {{ env }}
{% endfor %}
{% endif %}

# Konfiguracja dla procesu związanego z LLM
{% if item.is_llm_related is defined and item.is_llm_related %}
# Konfiguracja specyficzna dla LLM
export DIGITAL_TWIN_LLM=true
export DIGITAL_TWIN_LLM_ORIGINAL_PID={{ item.pid }}
{% endif %}

# Funkcja obsługi sygnałów
function cleanup() {
    echo "Zatrzymywanie procesu {{ item.name }} - $(date)"
    exit 0
}

# Rejestracja obsługi sygnałów
trap cleanup SIGINT SIGTERM

# Uruchom proces z taką samą linią poleceń jak oryginał
echo "Wykonywanie: {% if item.cmdline is defined and item.cmdline|length > 0 %}{{ item.cmdline|join(' ') }}{% else %}{{ item.name }}{% endif %}"

{% if item.cmdline is defined and item.cmdline|length > 0 %}
exec {{ item.cmdline|join(' ') }}
{% else %}
exec {{ item.name }}
{% endif %}
"""

            # Szablon dla usługi systemd
            process_service_template = """[Unit]
Description=Digital Twin Process: {{ item.name }} (Original PID: {{ item.pid }})
After=network.target

[Service]
Type=simple
User={{ item.user | default('root') }}
ExecStart=/tmp/safetytwin-processes/process_{{ item.name }}_{{ item.pid }}.sh
Restart=on-failure
RestartSec=5
{% if item.cwd is defined %}
WorkingDirectory={{ item.cwd }}
{% endif %}

# Limitowanie zasobów, aby symulować oryginalne wykorzystanie
{% if item.cpu_percent is defined %}
CPUQuota={{ (item.cpu_percent * 1.5) | int }}%
{% endif %}
{% if item.memory_percent is defined and item.memory_limit_mb is defined %}
MemoryLimit={{ item.memory_limit_mb }}M
{% endif %}

[Install]
WantedBy=multi-user.target
"""

            # Szablon dla raportu stanu
            status_report_template = """=================================================================
     RAPORT STANU CYFROWEGO BLIŹNIAKA - {{ ansible_date_time.date }}
=================================================================

Wygenerowano: {{ ansible_date_time.iso8601 }}
Hostname: {{ ansible_hostname }}
System: {{ ansible_distribution }} {{ ansible_distribution_version }}
Kernel: {{ ansible_kernel }}

-----------------------------------------------------------------
STATYSTYKI SYSTEMOWE
-----------------------------------------------------------------
CPU: {{ ansible_processor_vcpus }} vCPUs
Pamięć: {{ (ansible_memtotal_mb / 1024) | round(2) }} GB
Obciążenie: {{ ansible_load.get('15min', 'N/A') }} (15 min avg)
Uptime: {{ ansible_uptime_seconds | int // 86400 }}d {{ ansible_uptime_seconds | int % 86400 // 3600 }}h {{ ansible_uptime_seconds | int % 3600 // 60 }}m

-----------------------------------------------------------------
SKONFIGUROWANE USŁUGI
-----------------------------------------------------------------
Usługi systemd: {{ service_config.services | selectattr('type', 'equalto', 'systemd') | list | length }}
Kontenery Docker: {{ service_config.services | selectattr('type', 'equalto', 'docker') | list | length }}
Niezależne procesy: {{ service_config.processes | length }}

-----------------------------------------------------------------
USŁUGI SYSTEMD
-----------------------------------------------------------------
{% for service in service_config.services if service.type == 'systemd' %}
- {{ service.name }}: {{ service.state | upper }}{% if service.is_llm_related is defined and service.is_llm_related %} [LLM]{% endif %}
{% else %}
Brak skonfigurowanych usług systemd.
{% endfor %}

-----------------------------------------------------------------
KONTENERY DOCKER
-----------------------------------------------------------------
{% for service in service_config.services if service.type == 'docker' %}
- {{ service.name }}: {{ service.state | upper }}
  Obraz: {{ service.image }}
  {% if service.ports is defined and service.ports | length > 0 %}
  Porty: {% for port in service.ports %}{{ port.host_port }}:{{ port.container_port }}{% if not loop.last %}, {% endif %}{% endfor %}
  {% endif %}
  {% if service.is_llm_related is defined and service.is_llm_related %}
  [LLM]
  {% endif %}
{% else %}
Brak skonfigurowanych kontenerów Docker.
{% endfor %}

-----------------------------------------------------------------
NIEZALEŻNE PROCESY
-----------------------------------------------------------------
{% for process in service_config.processes %}
- {{ process.name }} (PID: {{ process.pid }}): {{ process.user | default('root') }}
  CPU: {{ process.cpu_percent | default(0) | round(2) }}%, Pamięć: {{ process.memory_percent | default(0) | round(2) }}%
  {% if process.is_llm_related is defined and process.is_llm_related %}
  [LLM]
  {% endif %}
{% else %}
Brak skonfigurowanych niezależnych procesów.
{% endfor %}

-----------------------------------------------------------------
STAN FAKTYCZNY SYSTEMU
-----------------------------------------------------------------
Działające usługi systemd: {{ status_systemd }}
Działające kontenery Docker: {{ status_docker }}
Całkowita liczba procesów: {{ ansible_processor_threads_per_core * ansible_processor_vcpus }}

-----------------------------------------------------------------
UWAGI
-----------------------------------------------------------------
{% if has_llm is defined and has_llm %}
[x] Wykryto komponenty związane z LLM
{% else %}
[ ] Nie wykryto komponentów związanych z LLM
{% endif %}

{% if service_config.services | selectattr('type', 'equalto', 'docker') | selectattr('state', 'equalto', 'running') | list | length > 0 %}
[x] Działające kontenery Docker wymagają dostępu do internetu
{% else %}
[ ] Brak działających kontenerów Docker
{% endif %}

{% if service_config.processes | length > 10 %}
[!] Duża liczba niezależnych procesów ({{ service_config.processes | length }}) może wpływać na wydajność systemu
{% endif %}

=================================================================
                   KONIEC RAPORTU STANU
=================================================================
"""

            # Zapisz szablony do plików
            with open(os.path.join(self.templates_dir, "process_launcher.sh.j2"), "w") as f:
                f.write(process_launcher_template)

            with open(os.path.join(self.templates_dir, "process_service.service.j2"), "w") as f:
                f.write(process_service_template)

            with open(os.path.join(self.templates_dir, "status_report.j2"), "w") as f:
                f.write(status_report_template)

            logger.info(f"Utworzono domyślne szablony w katalogu {self.templates_dir}")
        except Exception as e:
            logger.error(f"Bł