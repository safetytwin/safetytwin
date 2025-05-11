#!/bin/bash
# Skrypt: generate_install_result.sh
# Opis: Generuje plik INSTALL_RESULT.yaml z aktualnym stanem instalacji safetytwin
# Autor: AI Cascade

RESULT_FILE="INSTALL_RESULT.yaml"
DATE_NOW="$(date '+%Y-%m-%d %H:%M')"

# Helper: check service status
svc_status() {
  systemctl is-active --quiet "$1" && echo true || echo false
}

# Helper: check path exists
path_exists() {
  [ -e "$1" ] && echo true || echo false
}

# Helper: check CLI command
cli_exists() {
  command -v "$1" &>/dev/null && echo true || echo false
}

cat > "$RESULT_FILE" <<EOF
# Stan po instalacji safetytwin ($DATE_NOW)

safetytwin_installation:
  agent:
    installed: "+$(svc_status safetytwin-agent)"
    status: $(svc_status safetytwin-agent)
    message: "Agent safetytwin zainstalowany: $(svc_status safetytwin-agent)"
  bridge:
    installed: "+$(svc_status safetytwin-bridge)"
    status: $(svc_status safetytwin-bridge)
    message: "Usługa safetytwin bridge zainstalowana: $(svc_status safetytwin-bridge)"
  vm:
    image_downloaded: $(path_exists /var/lib/safetytwin/images/ubuntu-base.img)
    image_path: "/var/lib/safetytwin/images/ubuntu-base.img"
    image_resized: $(path_exists /var/lib/safetytwin/images/ubuntu-base.img)
    vm_defined: $(virsh list --all | grep -q safetytwin-vm && echo true || echo false)
    vm_started: $(virsh list --state-running | grep -q safetytwin-vm && echo true || echo false)
    cloud_init:
      status: "unknown"
      message: "Automatyczna detekcja statusu cloud-init/SSH wymaga logiki dostosowanej do twojej infrastruktury."
      ssh_connected: false
      recommendation: |
        Sprawdź konsolę VM:
          virsh console safetytwin-vm
        oraz konfigurację sieci (NAT/DHCP/mostek) w libvirt.
  directories:
    - path: "/var/lib/safetytwin/"
      exists: $(path_exists /var/lib/safetytwin/)
    - path: "/etc/safetytwin/"
      exists: $(path_exists /etc/safetytwin/)
    - path: "/var/log/safetytwin/"
      exists: $(path_exists /var/log/safetytwin/)
    - path: "/var/lib/safetytwin/images/"
      exists: $(path_exists /var/lib/safetytwin/images/)
    - path: "/etc/safetytwin/ssh/"
      exists: $(path_exists /etc/safetytwin/ssh/)
  ssh_keys:
    generated: $(path_exists /etc/safetytwin/ssh/id_rsa)
    path: "/etc/safetytwin/ssh/"
  cli:
    installed: $(cli_exists safetytwin)
    path: "/usr/local/bin/safetytwin"
    commands:
      - status
      - agent-log
      - bridge-log
      - cron-list
      - cron-add
      - cron-remove
      - cron-status
      - what
  monitoring:
    storage:
      script_installed: $(path_exists /usr/local/bin/monitor_storage.sh)
      cron_added: $(crontab -l 2>/dev/null | grep -q monitor_storage.sh && echo true || echo false)
      status: OK
  services:
    libvirtd:
      active: $(svc_status libvirtd)
    safetytwin-agent:
      active: $(svc_status safetytwin-agent)
    safetytwin-bridge:
      active: $(svc_status safetytwin-bridge)
  summary:
    success: unknown
    message: |
      Ten plik został wygenerowany automatycznie. Sprawdź szczegóły powyżej, aby ocenić stan instalacji safetytwin.
    recommendations:
      - Sprawdź logi usług i konsolę VM jeśli są problemy z połączeniem SSH.
      - Zweryfikuj katalogi i status usług.
EOF

chmod 644 "$RESULT_FILE"
echo "Wygenerowano $RESULT_FILE."
