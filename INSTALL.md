# Instrukcja instalacji i uruchomienia safetytwin

## Spis treści
- [Wymagania systemowe](#wymagania-systemowe)
- [Instalacja](#instalacja)
- [Jak to działa](#jak-to-dziala)
- [CLI: Zarządzanie systemem](#cli-zarzadzanie-systemem)
- [Troubleshooting (Rozwiązywanie problemów)](#troubleshooting)

---

## Wymagania systemowe
- System Linux: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch, openSUSE
- Uprawnienia root (sudo)
- Połączenie z Internetem

## Instalacja
1. **Pobierz repozytorium i przejdź do katalogu projektu:**
   ```bash
   git clone <repo-url>
   cd safetytwin/safetytwin
   ```
2. **Uruchom instalator jako root:**
   ```bash
   sudo bash install.sh
   ```
   Skrypt wykona automatycznie:
   - Instalację zależności systemowych i pythonowych
   - Konfigurację usług (libvirt, qemu, safetytwin bridge)
   - Utworzenie katalogów i kluczy SSH
   - Instalację CLI `safetytwin`
   - Dodanie monitoringu storage do crona
   - Przygotowanie bazowego obrazu safetytwin

3. **Po instalacji sprawdź status:**
   ```bash
   safetytwin status
   ```

---

## Jak to działa
- **safetytwin bridge** tworzy i zarządza maszyną wirtualną na bazie obrazu Ubuntu.
- **Agent safetytwin** zbiera dane o systemie i usługach (CPU, RAM, dyski, procesy, sieć, itp.).
- **CLI `safetytwin`** pozwala zarządzać usługami, logami i monitorowaniem:
  - `status` — status usług
  - `agent-log` — logi agenta
  - `bridge-log` — logi safetytwin bridge
  - `cron-list`, `cron-add`, `cron-remove`, `cron-status` — zarządzanie monitoringiem storage
  - `what` — ostatnie akcje z logów
- **Monitoring storage** — automatycznie sprawdza wolne miejsce na dysku.

---

## CLI: Zarządzanie systemem
Przykładowe polecenia:
```bash
safetytwin status         # Sprawdź status usług
safetytwin agent-log      # Zobacz logi agenta
safetytwin bridge-log     # Zobacz logi safetytwin bridge
safetytwin cron-list      # Sprawdź zadania cron monitoringu
safetytwin cron-add       # Dodaj monitoring do crona
safetytwin cron-remove    # Usuń monitoring z crona
safetytwin cron-status    # Status monitoringu storage
safetytwin what           # Ostatnie akcje z logów
```

---

## Troubleshooting

### Najczęstsze problemy i rozwiązania

**1. Brak pakietów systemowych (np. genisoimage, libvirt):**
- Uruchom ponownie instalator (`sudo bash install.sh`).
- Upewnij się, że masz połączenie z Internetem i aktualne repozytoria.

**2. Błąd: `genisoimage: command not found` lub `mkisofs: command not found`**
- Upewnij się, że pakiet `genisoimage` (Ubuntu/Debian/Fedora/openSUSE) lub `cdrtools` (Arch) jest zainstalowany.
- Instalator automatycznie instaluje te pakiety — jeśli coś poszło nie tak, zainstaluj ręcznie:
  ```bash
  sudo apt-get install genisoimage        # Ubuntu/Debian
  sudo dnf install genisoimage            # Fedora
  sudo zypper install genisoimage         # openSUSE
  sudo pacman -S cdrtools                 # Arch
  ```

**3. Błąd PEP 668: `externally-managed-environment` przy pip**
- Instalator używa apt do instalacji większości pakietów Python na Ubuntu/Debian.
- `deepdiff` i `ansible` są instalowane przez pip z flagą `--break-system-packages`.
- Jeśli pojawi się błąd, uruchom:
  ```bash
  pip3 install --break-system-packages deepdiff ansible
  ```

**4. Usługa libvirtd nie działa**
- Sprawdź status:
  ```bash
  sudo systemctl status libvirtd
  sudo systemctl start libvirtd
  ```
- Upewnij się, że użytkownik należy do grupy `libvirt`:
  ```bash
  sudo usermod -aG libvirt $USER
  # Wyloguj się i zaloguj ponownie
  ```

**5. Brak polecenia `safetytwin` po instalacji**
- Upewnij się, że `/usr/local/bin` jest w twoim `$PATH`.
- Jeśli nie, dodaj do `~/.bashrc` lub `~/.zshrc`:
  ```bash
  export PATH=$PATH:/usr/local/bin
  ```

**6. Inne błędy**
- Sprawdź logi:
  - `/var/log/safetytwin/safetytwin-bridge.log`
  - `journalctl -u safetytwin-agent.service`
  - `journalctl -u safetytwin-bridge.service`
- Zgłoś problem z pełnym logiem na GitLab/GitHub projektu.

---

## Kontakt i wsparcie
Masz problem? Zgłoś issue na repozytorium lub napisz do autora: Tom Sapletta
