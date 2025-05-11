#!/bin/bash
# Skrypt do ustawiania hasła root w cloud-init user-data
set -euo pipefail

USER_DATA="/var/lib/safetytwin/cloud-init/user-data"

if ! command -v mkpasswd &>/dev/null; then
  echo "[ERR] Zainstaluj pakiet 'whois' (zawiera mkpasswd): sudo apt install whois" >&2
  exit 1
fi

read -rsp "Podaj nowe hasło dla root (nie będzie widoczne): " PASSWD

echo
HASH=$(mkpasswd --method=SHA-512 "$PASSWD")

# Zmień lub dodaj hashed_passwd w sekcji root user
if grep -q 'hashed_passwd:' "$USER_DATA"; then
  sed -i "s|hashed_passwd:.*|hashed_passwd: $HASH|" "$USER_DATA"
else
  # Dodaj hashed_passwd jeśli nie istnieje
  sed -i "/- name: root/a \\    hashed_passwd: $HASH" "$USER_DATA"
fi

# Upewnij się, że są ustawione odpowiednie opcje
if ! grep -q 'lock_passwd:' "$USER_DATA"; then
  sed -i "/- name: root/a \\    lock_passwd: false" "$USER_DATA"
fi
if ! grep -q 'ssh_pwauth:' "$USER_DATA"; then
  echo 'ssh_pwauth: true' >> "$USER_DATA"
fi

chmod 600 "$USER_DATA"
echo "[OK] Hasło root zostało ustawione w $USER_DATA (hash). Nowe hasło będzie aktywne przy następnym starcie VM."
