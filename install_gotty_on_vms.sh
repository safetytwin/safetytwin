#!/bin/bash
# Skrypt automatycznej instalacji gotty na wszystkich VM z użyciem danych z .env
# Wymaga: sshpass, gotty (na hoście), pliku .env w katalogu głównym projektu

set -e
cd "$(dirname "$0")"

# Wczytaj dane z .env
if [ -f ../.env ]; then
  export $(grep -v '^#' ../.env | xargs)
else
  echo "Brak pliku .env!" >&2
  exit 1
fi

if [ -z "$VM_USER" ] || [ -z "$VM_PASS" ]; then
  echo "Brak VM_USER lub VM_PASS w pliku .env!" >&2
  exit 2
fi

# Pobierz listę VM (nazwa i IP)
mapfile -t VM_LIST < <(virsh list --all | awk 'NR>2 && $2!="" {print $2}')

for VM in "${VM_LIST[@]}"; do
  IP=$(virsh domifaddr "$VM" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
  if [ -z "$IP" ]; then
    echo "[WARN] VM $VM nie ma IP, pomijam..."
    continue
  fi
  echo "[INFO] Instaluję gotty na $VM ($IP)"
    # Pobierz i zainstaluj najnowszą binarkę gotty z GitHub API
  sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$IP" '
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
      PATTERN="gotty_linux_amd64$"
    elif [[ "$ARCH" == "aarch64" ]]; then
      PATTERN="gotty_linux_arm64$"
    else
      echo "[ERR] Nieobsługiwana architektura: $ARCH" >&2; exit 1
    fi
    API_URL="https://api.github.com/repos/gottyserver/gotty/releases/latest"
    ASSET_URL=$(curl -s "$API_URL" | grep browser_download_url | grep -E "$PATTERN" | cut -d '"' -f 4)
    if [ -z "$ASSET_URL" ]; then
      echo "[ERR] Nie znaleziono binarki gotty dla arch: $ARCH" >&2; exit 2
    fi
    echo "[INFO] Pobieram $ASSET_URL"
    wget -O /tmp/gotty "$ASSET_URL" && sudo mv /tmp/gotty /usr/local/bin/ && sudo chmod +x /usr/local/bin/gotty
    gotty --version
  '
  echo "[INFO] Tworzę usługę systemd dla gotty na VM $VM"
  cat > /tmp/gotty.service <<EOF
[Unit]
Description=GoTTY Web Terminal
After=network.target

[Service]
ExecStart=/usr/local/bin/gotty --port 8080 --permit-write --reconnect /bin/bash
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  scp -o StrictHostKeyChecking=no /tmp/gotty.service "$VM_USER@$IP:/tmp/gotty.service"
  sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$IP" 'sudo mv /tmp/gotty.service /etc/systemd/system/gotty.service'
  sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$IP" 'sudo systemctl daemon-reload'
  sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$IP" 'sudo systemctl enable --now gotty.service'
  sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$IP" 'sleep 2 && sudo systemctl status gotty --no-pager'
  rm /tmp/gotty.service
  echo "[OK] gotty powinno działać na http://$IP:8080/"
done
