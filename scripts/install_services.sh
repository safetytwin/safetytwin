#!/bin/bash
# Skrypt do instalacji wszystkich plików .service z katalogu services do /etc/systemd/system
set -e
SERVICES_DIR="$(dirname "$0")/../services"

if [ ! -d "$SERVICES_DIR" ]; then
  echo "Brak katalogu $SERVICES_DIR! Najpierw wygeneruj pliki .service."
  exit 1
fi

for svc in "$SERVICES_DIR"/*.service; do
  echo "Kopiuję $svc do /etc/systemd/system/"
  sudo cp "$svc" /etc/systemd/system/
  sudo chmod 644 "/etc/systemd/system/$(basename "$svc")"
  sudo systemctl daemon-reload
  echo "Zainstalowano: $(basename "$svc")"
done

echo "Wszystkie pliki .service zostały zainstalowane."
