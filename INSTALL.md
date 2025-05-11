---

## 📚 Menu nawigacyjne

- [README (Start)](README.md)
- [Instrukcja instalacji](INSTALL.md)
- [Stan instalatora](INSTALL_STATE.md)
- [Wynik instalacji](INSTALL_RESULT.yaml)
- [FAQ](docs/faq.md)
- [Rozwiązywanie problemów](docs/troubleshooting.md)
- [Przegląd architektury](docs/overview.md)
- [Agent](docs/agent.md)
- [VM Bridge](docs/vm-bridge.md)
- [Ansible](docs/ansible.md)
- [API](docs/api.md)
- [Strategia](STRATEGIA.md)

---

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
2. **Automatyczne środowisko Python venv:**
   Instalator sam utworzy środowisko wirtualne Pythona (`.venv`) w katalogu projektu i zainstaluje zależności pip do venv (nie globalnie). Jeśli środowisko już istnieje, zostanie użyte ponownie.
   
   Po instalacji możesz aktywować środowisko:
   ```bash
   source .venv/bin/activate
   ```
   
   Lub uruchomić instalator:
   ```bash
   sudo bash install.sh
   ```
   Skrypt wykona automatycznie:
   - Instalację zależności systemowych i pythonowych (w .venv)
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

## Automatyczna samonaprawa i diagnostyka VM

Instalator oraz skrypt `repair.sh` wyposażone są w mechanizmy samonaprawcze i diagnostyczne:

- Automatycznie diagnozują i naprawiają najczęstsze problemy z siecią VM (libvirt, cloud-init, DHCP).
- Skrypt `repair.sh` zamyka aktywne sesje konsoli VM przed próbą zebrania diagnostyki.
- Zbiera szczegółowe logi i konfiguracje z VM do pliku `/var/lib/safetytwin/TWIN.yaml`.
- Jeśli automatyczna diagnostyka się nie powiedzie, generuje jasne instrukcje ręczne dla użytkownika.

Po każdej instalacji oraz naprawie generowany jest plik `INSTALL_RESULT.yaml` oraz (przy diagnostyce VM) `TWIN.yaml` z aktualnym stanem systemu i zaleceniami naprawczymi.

Instalator safetytwin został wyposażony w mechanizmy samonaprawcze. Jeśli wykryje typowe problemy (np. brak katalogów, nieaktywne usługi, brak CLI, brak obrazu VM, brak zadania w cronie, błędne uprawnienia), automatycznie podejmie próbę ich naprawy:

- Tworzy brakujące katalogi (`/var/lib/safetytwin/`, `/etc/safetytwin/`, `/var/log/safetytwin/`, `/var/lib/safetytwin/images/`, `/etc/safetytwin/ssh/`).
- Przywraca lub nadpisuje plik CLI `/usr/local/bin/safetytwin` z odpowiednimi uprawnieniami.
- Generuje klucze SSH jeśli nie istnieją.
- Restartuje i aktywuje usługi `safetytwin-agent`, `safetytwin-bridge`, `libvirtd`.
- Dodaje zadanie monitoringu storage do crona, jeśli go brakuje.
- Pobiera obraz VM jeśli nie istnieje.
- Naprawia uprawnienia do katalogów i plików.

Po każdej instalacji generowany jest plik `INSTALL_RESULT.yaml`, który zawiera aktualny stan systemu i zalecenia naprawcze.

### Zalecenia
- Instalator należy zawsze uruchamiać z uprawnieniami root: `sudo bash install.sh`.
- Jeśli napotkasz problem, uruchom instalator ponownie — większość błędów zostanie automatycznie naprawiona.
- Sprawdź plik `INSTALL_RESULT.yaml` po instalacji, aby zobaczyć szczegółowy raport.

## Troubleshooting

### Nowość: plik diagnostyczny TWIN.yaml

Jeśli napotkasz problemy z siecią lub uruchomieniem VM, uruchom `sudo bash repair.sh`. Skrypt wygeneruje plik `/var/lib/safetytwin/TWIN.yaml` ze szczegółową diagnostyką VM. Jeśli pojawią się sekcje oznaczone `[BŁĄD]`, postępuj zgodnie z instrukcjami w pliku lub zgłoś problem wraz z jego zawartością do wsparcia.

Jeśli napotkasz problemy podczas instalacji lub działania safetytwin, sprawdź poniższe punkty:

- Upewnij się, że uruchamiasz instalator jako root (`sudo bash install.sh`).
- Sprawdź logi w `/var/log/safetytwin/`.
- Zweryfikuj status usług: `systemctl status safetytwin-agent safetytwin-bridge libvirtd`.
- Sprawdź czy katalogi `/var/lib/safetytwin/`, `/etc/safetytwin/`, `/var/log/safetytwin/` istnieją.
- Upewnij się, że CLI `safetytwin` działa (`safetytwin status`).
- Sprawdź czy obraz VM jest pobrany: `/var/lib/safetytwin/images/ubuntu-base.img`.
- Sprawdź czy monitoring storage jest aktywny w cronie (`crontab -l | grep monitor_storage.sh`).

Jeśli problem nie ustępuje, uruchom instalator ponownie lub przejrzyj wygenerowany plik `INSTALL_RESULT.yaml`.

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
