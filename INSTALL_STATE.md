# Deklaratywny opis stanu instalatora safetytwin

Ten dokument podsumowuje, co dokładnie wykonuje aktualny instalator `install.sh` dla projektu safetytwin. Pozwala szybko przeanalizować, jakie komponenty są instalowane, konfigurowane i jakie efekty są osiągane po uruchomieniu skryptu.

---

## 1. Wykrywanie systemu
- Rozpoznaje dystrybucję Linuxa (Ubuntu/Debian, Fedora/RHEL/CentOS, Arch, openSUSE).
- Dostosowuje polecenia instalacji pakietów do systemu.

## 2. Instalacja zależności systemowych
- Instaluje (jeśli brak):
  - libvirt (demon, klient, nagłówki)
  - qemu (emulator)
  - python3, python3-dev, python3-pip
  - gcc, make, pkg-config
  - narzędzie do tworzenia ISO:
    - Ubuntu/Debian/Fedora/openSUSE: `genisoimage`
    - Arch: `cdrtools`

## 3. Konfiguracja i uruchomienie usług
- Włącza i uruchamia usługę `libvirtd` (demon libvirt).
- Sprawdza dostępność poleceń `virsh`, `qemu-system-x86_64` oraz aktywność `libvirtd`.

## 4. Instalacja zależności Python
- Ubuntu/Debian:
  - Przez apt: `python3-libvirt`, `python3-flask`, `python3-flask-cors`, `python3-yaml`, `python3-paramiko`, `python3-gunicorn`, `python3-werkzeug`, `python3-pytest`
  - Przez pip (`--break-system-packages`): `deepdiff`, `ansible`
- Inne systemy: wszystko przez pip.

## 5. Tworzenie katalogów projektu
- /opt/safetytwin
- /etc/safetytwin
- /var/lib/safetytwin
- /var/log/safetytwin
- /var/lib/safetytwin/images
- /etc/safetytwin/ssh

## 6. Konfiguracja monitoringu storage
- Tworzy/aktualizuje skrypt monitorujący miejsce na dysku.
- Dodaje zadanie cron do automatycznego monitorowania storage.

## 7. Instalacja CLI
- Instaluje narzędzie `/usr/local/bin/safetytwin` z obsługą poleceń:
  - `status`, `agent-log`, `bridge-log`, `cron-list`, `cron-add`, `cron-remove`, `cron-status`, `what`

## 8. Generowanie kluczy SSH
- Tworzy parę kluczy RSA w `/etc/safetytwin/ssh/` do komunikacji z maszyną wirtualną.

## 9. Przygotowanie bazowego obrazu maszyny wirtualnej
- Pobiera minimalny obraz Ubuntu (cloud image) do `/var/lib/safetytwin/images/ubuntu-base.img`.
- Dostosowuje obraz (np. powiększa, generuje ISO cloud-init).

## 10. Instalacja i konfiguracja usług safetytwin
- Instalacja i aktywacja agenta monitorującego.
- Instalacja i aktywacja usługi safetytwin bridge.

---

## Efekt końcowy
Po poprawnym uruchomieniu instalatora:
- Wszystkie wymagane pakiety są obecne.
- Usługi `libvirtd`, `safetytwin-agent`, `safetytwin-bridge` są aktywne.
- Dostępne jest CLI `safetytwin` do zarządzania systemem.
- Monitoring storage działa automatycznie (cron).
- Gotowy bazowy obraz VM do dalszego wykorzystania.

---

## Szybka diagnostyka (co sprawdzić po instalacji)
- Czy działa: `safetytwin status`
- Czy działa: `virsh list --all`, `qemu-system-x86_64 --version`
- Czy katalogi `/var/lib/safetytwin/`, `/etc/safetytwin/` istnieją
- Czy są logi w `/var/log/safetytwin/`
- Czy zadanie cron monitoruje storage

---

## Aktualizacja
Ten dokument należy aktualizować przy każdej zmianie logiki instalatora!
