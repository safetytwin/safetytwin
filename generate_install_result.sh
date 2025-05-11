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

  files:
    config:
      - path: "/etc/safetytwin/agent-config.json"
      - path: "/etc/safetytwin/bridge-config.yaml"
      - path: "/etc/safetytwin/ssh/id_rsa"
      - path: "/etc/safetytwin/ssh/id_rsa.pub"
      - path: "/etc/safetytwin/inventory.yml"
    systemd_units:
      - path: "/etc/systemd/system/safetytwin-agent.service"
      - path: "/etc/systemd/system/safetytwin-bridge.service"
    cloud_init:
      - path: "/var/lib/safetytwin/cloud-init/user-data"
      - path: "/var/lib/safetytwin/cloud-init/meta-data"
    vm:
      - path: "/var/lib/safetytwin/images/ubuntu-base.img"
      - path: "/var/lib/safetytwin/vm-definition.xml"
    logs:
      - path: "/var/log/safetytwin/agent.log"
      - path: "/var/log/safetytwin/bridge.log"
      - path: "/var/log/safetytwin/storage.log"
      - path: "/var/log/cloud-init.log"
      - path: "/var/log/cloud-init-output.log"
      - path: "/var/log/syslog"
      - path: "/var/log/messages"
    cron:
      - path: "(crontab -l | grep monitor_storage.sh)"

  files_status:
$(for f in "/etc/safetytwin/agent-config.json" "/etc/safetytwin/bridge-config.yaml" "/etc/safetytwin/ssh/id_rsa" "/etc/safetytwin/ssh/id_rsa.pub" "/etc/safetytwin/inventory.yml" "/etc/systemd/system/safetytwin-agent.service" "/etc/systemd/system/safetytwin-bridge.service" "/var/lib/safetytwin/cloud-init/user-data" "/var/lib/safetytwin/cloud-init/meta-data" "/var/lib/safetytwin/images/ubuntu-base.img" "/var/lib/safetytwin/vm-definition.xml" "/var/log/safetytwin/agent.log" "/var/log/safetytwin/bridge.log" "/var/log/safetytwin/storage.log" "/var/log/cloud-init.log" "/var/log/cloud-init-output.log" "/var/log/syslog" "/var/log/messages"; do
  if [ -e "$f" ]; then
    echo "    - path: $f"
    echo "      exists: true"
    echo "      mtime: $(stat -c %y "$f" 2>/dev/null)"
    echo "      size: $(stat -c %s "$f" 2>/dev/null)"
    if [[ "$f" == *.log ]]; then
      echo "      tail: |"
      tail -n 10 "$f" 2>/dev/null | sed 's/^/        /'
    fi
  else
    echo "    - path: $f"
    echo "      exists: false"
  fi
 done)

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

  diagnostics:
    commands:
      - sudo journalctl -u safetytwin-agent
      - sudo journalctl -u safetytwin-bridge
      - sudo systemctl status safetytwin-agent safetytwin-bridge
      - sudo virsh console safetytwin-vm
      - sudo virsh domiflist safetytwin-vm
      - sudo virsh net-list --all
      - sudo virsh net-info default
      - sudo cat /var/log/cloud-init.log
      - sudo cat /var/log/cloud-init-output.log
      - sudo cat /var/log/safetytwin/agent.log
      - sudo cat /var/log/safetytwin/bridge.log
      - sudo cat /var/log/safetytwin/storage.log
      - sudo cat /var/log/syslog
      - sudo cat /var/log/messages
      - sudo crontab -l | grep monitor_storage.sh
EOF


chmod 644 "$RESULT_FILE"
echo "Wygenerowano $RESULT_FILE."
