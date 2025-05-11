package collectors

import (
	"safetytwin/agent/models"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// CollectServicesInfo zbiera informacje o usługach systemowych
func CollectServicesInfo() ([]models.Service, error) {
	// Zbierz usługi systemd
	systemdServices, err := collectSystemdServices()
	if err != nil {
		// Logujemy błąd, ale kontynuujemy, aby zebrać inne typy usług
		fmt.Printf("Błąd podczas zbierania usług systemd: %v\n", err)
	}

	// Zbierz kontenery Docker
	dockerContainers, err := CollectDockerContainers()
	if err != nil {
		// Logujemy błąd, ale kontynuujemy
		fmt.Printf("Błąd podczas zbierania kontenerów Docker: %v\n", err)
	}

	// Połącz wszystkie usługi
	services := make([]models.Service, 0)
	services = append(services, systemdServices...)
	services = append(services, dockerContainers...)

	return services, nil
}

// collectSystemdServices zbiera informacje o usługach systemd
func collectSystemdServices() ([]models.Service, error) {
	services := make([]models.Service, 0)
	hostname, _ := getHostname()

	// Sprawdź, czy systemd jest dostępny
	if _, err := os.Stat("/run/systemd/system"); os.IsNotExist(err) {
		return services, fmt.Errorf("systemd nie jest dostępny na tym systemie")
	}

	// Użyj systemctl do pobrania listy usług
	cmd := exec.Command("systemctl", "list-units", "--type=service", "--all", "--no-pager", "--plain")
	output, err := cmd.Output()
	if err != nil {
		return services, fmt.Errorf("błąd podczas wykonywania komendy systemctl: %v", err)
	}

	// Przetwórz wynik
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}

		// Pobierz nazwę usługi (usuwając '.service')
		serviceName := fields[0]
		if !strings.HasSuffix(serviceName, ".service") {
			continue
		}
		serviceName = strings.TrimSuffix(serviceName, ".service")

		// Utwórz podstawowy obiekt usługi
		service := models.Service{
			Name:      serviceName,
			Type:      "systemd",
			Hostname:  hostname,
			Timestamp: time.Now().Format(time.RFC3339),
		}

		// Pobierz status usługi
		serviceStatus := fields[3]
		if serviceStatus == "running" || serviceStatus == "active" {
			service.Status = "active"
		} else {
			service.Status = "inactive"
		}

		// Pobierz więcej informacji o usłudze
		cmd = exec.Command("systemctl", "show", serviceName, "--property=MainPID", "--property=ExecMainStartTimestamp")
		detailOutput, err := cmd.Output()
		if err == nil {
			details := string(detailOutput)

			// Pobierz PID
			pidLine := extractProperty(details, "MainPID")
			if pidLine != "" && pidLine != "0" {
				var pid int32
				if _, err := fmt.Sscanf(pidLine, "%d", &pid); err == nil && pid > 0 {
					service.PID = pid
				}
			}

			// Pobierz czas uruchomienia
			startTimeLine := extractProperty(details, "ExecMainStartTimestamp")
			if startTimeLine != "" {
				startTime, err := parseSystemdTime(startTimeLine)
				if err == nil {
					service.StartTime = startTime.Format(time.RFC3339)
					service.UptimeSeconds = int64(time.Since(startTime).Seconds())
				}
			}
		}

		// Sprawdź, czy usługa jest związana z LLM
		service.IsLLMRelated = isLLMService(serviceName)

		// Dodaj usługę do listy
		services = append(services, service)
	}

	return services, nil
}

// extractProperty wyciąga wartość właściwości z wyjścia systemctl show
func extractProperty(output, property string) string {
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, property+"=") {
			return strings.TrimPrefix(line, property+"=")
		}
	}
	return ""
}

// parseSystemdTime parsuje czas systemd, np. "Tue 2021-05-04 12:34:56 CEST"
func parseSystemdTime(timeStr string) (time.Time, error) {
	formats := []string{
		"Mon 2006-01-02 15:04:05 MST",
		"2006-01-02 15:04:05 MST",
		"Mon 2006-01-02 15:04:05",
		"2006-01-02 15:04:05",
	}

	var lastErr error
	for _, format := range formats {
		t, err := time.Parse(format, timeStr)
		if err == nil {
			return t, nil
		}
		lastErr = err
	}

	return time.Time{}, lastErr
}

// isLLMService sprawdza, czy usługa systemd jest potencjalnie związana z LLM
func isLLMService(serviceName string) bool {
	serviceLower := strings.ToLower(serviceName)
	for _, keyword := range llmKeywords {
		if strings.Contains(serviceLower, keyword) {
			return true
		}
	}

	// Sprawdź, czy usługa ma proces, który jest związany z LLM
	cmd := exec.Command("systemctl", "show", serviceName+".service", "--property=MainPID")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	pidLine := strings.TrimSpace(string(output))
	if !strings.HasPrefix(pidLine, "MainPID=") {
		return false
	}

	pidStr := strings.TrimPrefix(pidLine, "MainPID=")
	if pidStr == "0" {
		return false
	}

	var pid int32
	if _, err := fmt.Sscanf(pidStr, "%d", &pid); err != nil {
		return false
	}

	// Sprawdź, czy proces o danym PID jest związany z LLM
	processes, err := process.Processes()
	if err != nil {
		return false
	}

	for _, proc := range processes {
		if proc.Pid == int32(pid) {
			name, err := proc.Name()
			if err != nil {
				continue
			}

			cmdline, err := proc.Cmdline()
			if err != nil {
				continue
			}

			return isLLMProcess(proc, name, cmdline)
		}
	}

	return false
}

// getHostname zwraca nazwę hosta
func getHostname() (string, error) {
	hostname, err := os.Hostname()
	if err != nil {
		return "unknown", err
	}
	return hostname, nil
}

// FindServiceForPID znajduje usługę systemd dla danego PID
func FindServiceForPID(pid int32) (string, error) {
	cmd := exec.Command("systemctl", "status", fmt.Sprintf("%d", pid))
	output, err := cmd.Output()
	if err != nil {
		// Ignorujemy błąd, ponieważ komenda zwraca kod błędu, gdy proces nie jest usługą
		if len(output) == 0 {
			return "", fmt.Errorf("nie znaleziono usługi dla PID %d", pid)
		}
	}

	// Przetwórz wynik
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, ".service") {
			parts := strings.Fields(line)
			for _, part := range parts {
				if strings.HasSuffix(part, ".service") {
					return strings.TrimSuffix(part, ".service"), nil
				}
			}
		}
	}

	return "", fmt.Errorf("nie znaleziono usługi dla PID %d", pid)
}

// GetSystemdServiceStatus pobiera aktualny status usługi systemd
func GetSystemdServiceStatus(serviceName string) (string, error) {
	cmd := exec.Command("systemctl", "is-active", serviceName)
	output, err := cmd.Output()
	if err != nil {
		// Ignorujemy błąd, ponieważ komenda zwraca kod błędu, gdy usługa nie jest aktywna
		if len(output) == 0 {
			return "inactive", nil
		}
	}

	return strings.TrimSpace(string(output)), nil
}

// CollectLLMRelatedServices zbiera informacje tylko o usługach związanych z LLM
func CollectLLMRelatedServices() ([]models.Service, error) {
	services, err := CollectServicesInfo()
	if err != nil {
		return nil, err
	}

	llmServices := make([]models.Service, 0)
	for _, s := range services {
		if s.IsLLMRelated {
			llmServices = append(llmServices, s)
		}
	}

	return llmServices, nil
}