# Stan po instalacji safetytwin — raport deklaratywny

## Data instalacji: 2025-05-11 08:44

---

## 1. Instalacja agenta monitorującego
- [✔] Agent monitorujący zainstalowany pomyślnie.

## 2. Instalacja usługi safetytwin bridge
- [✔] Usługa safetytwin bridge zainstalowana pomyślnie.

## 3. Tworzenie bazowej maszyny wirtualnej
- [✔] Bazowy obraz Ubuntu został pobrany do `/var/lib/safetytwin/images/ubuntu-base.img`.
- [✔] Obraz został powiększony i przygotowany (genisoimage działa poprawnie).
- [✔] Definicja VM utworzona i uruchomiona (`virsh define` oraz `virsh start`).

## 4. Konfiguracja cloud-init i próba połączenia SSH
- [✗] VM uruchomiona, ale nie udało się uzyskać adresu IP oraz połączyć przez SSH (10 prób zakończonych niepowodzeniem).
- [!] Sugerowana akcja: sprawdź konsolę VM:
  ```
  virsh console safetytwin-vm
  ```
  oraz sieć/nat/dhcp w libvirt.

## 5. Katalogi i pliki projektu
- [✔] Katalogi `/var/lib/safetytwin/`, `/etc/safetytwin/`, `/var/log/safetytwin/` istnieją.
- [✔] Katalog `/var/lib/safetytwin/images/` zawiera pobrany obraz.
- [✔] Wygenerowano klucz SSH w `/etc/safetytwin/ssh/`.

## 6. CLI safetytwin
- [✔] Dostępne polecenie `safetytwin` w `/usr/local/bin/`.
- [✔] CLI obsługuje: `status`, `agent-log`, `bridge-log`, `cron-list`, `cron-add`, `cron-remove`, `cron-status`, `what`.

## 7. Monitoring storage
- [✔] Skrypt monitoringu zainstalowany i dodany do crona.

## 8. Usługi systemowe
- [✔] `libvirtd` aktywny
- [✔] `safetytwin-agent` aktywny
- [✔] `safetytwin-bridge` aktywny

---

## Podsumowanie
Instalacja przebiegła poprawnie do etapu uruchomienia VM. Problemem jest brak uzyskanego adresu IP VM i brak możliwości połączenia przez SSH. Pozostałe komponenty działają prawidłowo.

### Rekomendacje:
- Sprawdź logi libvirt i cloud-init VM.
- Sprawdź ustawienia sieci w libvirt (NAT, DHCP, mostek).
- Użyj `virsh console safetytwin-vm` do ręcznej diagnostyki maszyny.
- Upewnij się, że system hosta pozwala na forwarding i działa dnsmasq/dhcp.

---

## Szybka diagnostyka
- `safetytwin status`
- `virsh list --all`
- `journalctl -u safetytwin-agent.service`
- `journalctl -u safetytwin-bridge.service`
- `sudo virsh console safetytwin-vm`
- Sprawdź logi w `/var/log/safetytwin/`
