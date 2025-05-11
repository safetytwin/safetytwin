# Najczęściej zadawane pytania (FAQ)

## Podstawowe pytania

### Co to jest cyfrowy bliźniak?

Cyfrowy bliźniak to wirtualna reprezentacja fizycznego systemu, w tym przypadku komputera i działających na nim usług. Nasz system tworzy działającą kopię monitorowanego systemu w maszynie wirtualnej, która jest aktualizowana co 10 sekund, aby odzwierciedlać aktualny stan rzeczywistego systemu.

### Czym różni się ten projekt od tradycyjnych narzędzi monitorujących?

Tradycyjne narzędzia monitorujące (jak Nagios, Prometheus, Zabbix) tylko zbierają i wizualizują metryki. Nasz system idzie o krok dalej - tworzy faktycznie działającą kopię monitorowanego systemu, z uruchomionymi usługami i procesami. Dzięki temu możesz nie tylko obserwować stan systemu, ale także wchodzić z nim w interakcję, testować zmiany i analizować problemy w bezpiecznym środowisku.

### Czy system wymaga dużo zasobów?

System wymaga przynajmniej 8GB RAM (4GB dla systemu hosta i 4GB dla maszyny wirtualnej) oraz około 50GB wolnego miejsca na dysku. Obciążenie procesora jest zazwyczaj niskie, chyba że maszyna wirtualna wykonuje intensywne operacje.

### Jak często aktualizowany jest cyfrowy bliźniak?

Domyślnie system zbiera dane i aktualizuje cyfrowego bliźniaka co 10 sekund. Ten interwał można skonfigurować w zakresie od 1 sekundy do kilku minut, w zależności od wymagań.

## Instalacja i konfiguracja

### Czy mogę zainstalować system na innym systemie operacyjnym niż Linux?

Obecnie system jest zaprojektowany do działania na Linuksie ze względu na zależność od libvirt/KVM dla wirtualizacji. Nie ma wsparcia dla Windows lub macOS jako systemu hosta. Jednak agent zbierający dane może być skompilowany dla innych systemów operacyjnych, jeśli chcesz monitorować system inny niż Linux.

### Czy mogę monitorować wiele systemów jednocześnie?

Tak, możesz zainstalować agenta na wielu systemach i skonfigurować każdy z nich, aby wysyłał dane do tej samej instancji VM Bridge. Następnie możesz przełączać się między różnymi obrazami wirtualnymi dla poszczególnych systemów.

### Czy system działa w chmurze?

Tak, system może być uruchomiony w chmurze, pod warunkiem że dostawca chmury obsługuje zagnieżdżoną wirtualizację (nested virtualization). Większość dużych dostawców (AWS, GCP, Azure) oferuje instancje z obsługą zagnieżdżonej wirtualizacji.

### Jak zmienić interwał aktualizacji?

Interwał aktualizacji można zmienić w pliku konfiguracyjnym agenta (`/etc/digital-twin/agent-config.json`), edytując wartość parametru `interval`:

```json
{
  "interval": 5,  // Zmiana na 5 sekund
  ...
}
```

Po zmianie konfiguracji należy zrestartować usługę agenta:

```bash
sudo systemctl restart digital-twin-agent.service
```

## Użytkowanie i funkcje

### Jak uzyskać dostęp do cyfrowego bliźniaka?

Dostęp do maszyny wirtualnej cyfrowego bliźniaka można uzyskać na kilka sposobów:

1. Przez SSH:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP
```

2. Przez konsolę VNC, używając polecenia:
```bash
virt-viewer digital-twin-vm
```

3. Przez API REST, dostępne pod adresem:
```
http://VM_IP:5678/api/v1/
```

### Czy mogę wykonywać operacje na cyfrowym bliźniaku bez wpływu na rzeczywisty system?

Tak, to jest jedna z głównych zalet tego systemu. Możesz wykonywać dowolne operacje na cyfrowym bliźniaku, testować zmiany, symulować awarie itp., bez wpływu na rzeczywisty system. Wszelkie zmiany będą tylko na wirtualnej kopii.

### Jak mogę przywrócić poprzedni stan cyfrowego bliźniaka?

System automatycznie tworzy snapshoty VM przy każdej znaczącej zmianie. Możesz przywrócić dowolny snapshot za pomocą API REST:

```bash
curl -X POST http://VM_IP:5678/api/v1/snapshots/state_1620123456
```

Lub użyć interfejsu libvirt:

```bash
sudo virsh snapshot-revert digital-twin-vm state_1620123456
```

### Czy system obsługuje kontenery Docker?

Tak, system w pełni obsługuje monitorowanie i replikację kontenerów Docker. Jeśli na monitorowanym systemie działają kontenery Docker, zostaną one automatycznie wykryte i odtworzone w cyfrowym bliźniaku.

### Czy mogę monitorować procesy związane z LLM (Large Language Models)?

Tak, system ma specjalne wsparcie dla wykrywania i monitorowania procesów związanych z modelami językowymi. Agent automatycznie wykrywa procesy, które mogą być związane z LLM (np. Python uruchamiający biblioteki jak PyTorch, TensorFlow, Hugging Face itp.).

## Rozwiązywanie problemów

### Agent nie może połączyć się z VM Bridge

1. Sprawdź, czy adres IP VM w konfiguracji agenta jest poprawny:
```bash
cat /etc/digital-twin/agent-config.json
```

2. Sprawdź, czy VM Bridge działa na maszynie wirtualnej:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "systemctl status digital-twin-bridge"
```

3. Sprawdź, czy port jest otwarty na maszynie wirtualnej:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "netstat -tulpn | grep 5678"
```

### Maszyna wirtualna nie uruchamia się

1. Sprawdź status VM:
```bash
sudo virsh dominfo digital-twin-vm
```

2. Sprawdź logi KVM:
```bash
sudo tail -f /var/log/libvirt/qemu/digital-twin-vm.log
```

3. Spróbuj uruchomić VM ręcznie:
```bash
sudo virsh start digital-twin-vm
```

### VM Bridge nie aktualizuje stanu VM

1. Sprawdź logi VM Bridge:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "journalctl -fu digital-twin-bridge"
```

2. Sprawdź, czy Ansible działa poprawnie:
```bash
sudo ansible -i /etc/digital-twin/inventory.yml all -m ping
```

3. Sprawdź, czy VM Bridge otrzymuje dane od agenta:
```bash
ssh -i /etc/digital-twin/ssh/id_rsa root@VM_IP "tail -f /var/log/digital-twin/vm-bridge.log"
```

## Bezpieczeństwo i wydajność

### Czy system jest bezpieczny?

System używa izolacji maszyny wirtualnej, co zapewnia dobrą warstwę bezpieczeństwa. Jednakże, domyślnie używa hasła i klucza SSH, które są generowane podczas instalacji. Dla większego bezpieczeństwa zaleca się:

1. Zmianę domyślnego hasła roota na VM
2. Ograniczenie dostępu do API za pomocą zapory sieciowej
3. Używanie bezpiecznego kanału komunikacji (np. VPN) jeśli system jest używany w środowisku produkcyjnym

### Czy agent wpływa na wydajność monitorowanego systemu?

Agent jest zaprojektowany tak, aby miał minimalne obciążenie na monitorowany system. Typowo wykorzystuje mniej niż 1% CPU i około 50MB RAM. Dla większości systemów jest to niezauważalne obciążenie.

### Czy mogę zmienić ilość zasobów przydzielonych do VM?

Tak, można zmienić ilość pamięci i liczbę vCPU przydzielonych do maszyny wirtualnej:

```bash
# Zmiana ilości pamięci
sudo virsh setmaxmem digital-twin-vm 8G --config
sudo virsh setmem digital-twin-vm 8G --config

# Zmiana liczby vCPU
sudo virsh setvcpus digital-twin-vm 4 --config --maximum
sudo virsh setvcpus digital-twin-vm 4 --config

# Restart VM
sudo virsh shutdown digital-twin-vm
sudo virsh start digital-twin-vm
```

## Inne

### Jak mogę rozszerzyć lub dostosować system?

System jest modułowy i można go łatwo rozszerzyć lub dostosować:

1. **Agent**: Możesz dodać nowe kolektory danych w katalogu `agent/collectors/`
2. **VM Bridge**: Możesz dodać nowe endpointy API lub rozszerzyć logikę przetwarzania danych
3. **Ansible**: Możesz dostosować playbook `apply_services.yml` do własnych potrzeb
4. **Szablony**: Możesz dodać nowe szablony w katalogu `templates/`

### Czy projekt jest open source?

Tak, projekt jest udostępniony na licencji MIT. Możesz swobodnie używać, modyfikować i rozpowszechniać kod zgodnie z warunkami licencji.

### Czy mogę użyć innego rozwiązania wirtualizacyjnego niż libvirt/KVM?

Obecnie system jest zaprojektowany do pracy z libvirt/KVM, ale teoretycznie mógłby być dostosowany do innych rozwiązań wirtualizacyjnych jak VirtualBox, VMware lub nawet konteneryzacji. Wymagałoby to jednak znaczących zmian w kodzie VM Bridge.

### Jak zgłosić błąd lub zaproponować nową funkcję?

Błędy i propozycje nowych funkcji można zgłaszać na GitHub w zakładce Issues:
https://github.com/digital-twin-system/digital-twin/issues

### Gdzie mogę znaleźć więcej informacji?

- Dokumentacja projektu znajduje się w katalogu `docs/`
- Kod źródłowy z komentarzami
- [Strona projektu](https://github.com/digital-twin-system/digital-twin)
- [API dokumentacja](docs/API.md)