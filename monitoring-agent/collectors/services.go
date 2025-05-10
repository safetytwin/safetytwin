package collectors

import (
	"digital-twin/agent/models"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Słowa kluczowe do identyfikacji usług LLM
var llmKeywords = []string{
	"python", "python3", "llama", "gpt", "bert", "transformer",
	"pytorch", "tensorflow", "onnxruntime", "huggingface",
	"langchain", "llm", "openai", "mistral", "vicuna", "falcon",
}

// CollectServicesInfo zbiera informacje o usługach systemowych i kontenerach Docker
func CollectServicesInfo() ([]models.Service, error) {
	services := []models.Service{}
	
	// Zbierz informacje o usługach systemd
	systemdServices, err := collectSystemdServices()
	if err != nil {
		log.Printf("Błąd podczas zbierania informacji o usługach systemd: %v", err)
	} else {
		services = append(services, systemdServices...)
	}
	
	// Zbierz informacje o kontenerach Docker
	dockerContainers, err := collectDockerContainers()
	if err != nil {
		log.Printf("Błąd podczas zbierania informacji o kontenerach Docker: %v", err)
	} else {
		services = append(services, dockerContainers...)
	}
	
	return services, nil
}

// Zbieranie informacji o usługach systemd
func collectSystemdServices() ([]models.Service, error) {
	services := []models.Service{}
	
	// Sprawdź, czy systemd jest dostępny
	if _, err := os.Stat("/run/systemd/system"); os.IsNotExist(err) {
		log.Println("Systemd nie jest dostępny na tym systemie")
		return services, nil
	}
	
	// Wykonaj komendę systemctl
	cmd := exec.Command("systemctl", "list-units", "--type=service", "--all", "--no-pager")
	output, err := cmd.Output()
	if err != nil {
		return services, fmt.Errorf("błąd podczas wykonywania komendy systemctl: %v", err)
	}
	
	// Parsuj wynik
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.TrimSpace(line) == "" || strings.Contains(line, "UNIT") || strings.Contains(line, "LOAD") {
			continue
		}
		
		fields := strings.Fields(line)
		if len(fields) >= 3 && strings.HasSuffix(fields[0], ".service") {
			serviceName := fields[0]
			
			// Pobierz szczegółowe informacje o usłudze
			service := models.Service{
				Name:      serviceName,
				Type:      "systemd",
				Timestamp: time.Now().Format(time.RFC3339),
			}
			
			// Status usługi
			cmd = exec.Command("systemctl", "status", serviceName, "--no-pager")
			statusOutput, _ := cmd.Output()
			statusStr := string(statusOutput)
			
			// Wyciągnij status (active/inactive)
			if strings.Contains(statusStr, "Active: active") {
				service.Status = "active"
			} else if strings.Contains(statusStr, "Active: inactive") {
				service.Status = "inactive"
			} else {
				service.Status = "unknown"
			}
			
			// Wyciągnij PID
			pidMatch := strings.Index(statusStr, "Main PID: ")
			if pidMatch >= 0 {
				pidStr := statusStr[pidMatch+10:]
				pidEnd := strings.Index(pidStr, " ")
				if pidEnd > 0 {
					pidStr = pidStr[:pidEnd]
				}
				var pid int
				if _, err := fmt.Sscanf(pidStr, "%d", &pid); err == nil && pid > 0 {
					service.PID = pid
				}
			}
			
			services = append(services, service)
		}
	}
	
	return services, nil
}

// Zbieranie informacji o kontenerach Docker
func collectDockerContainers() ([]models.Service, error) {
	services := []models.Service{}
	
	// Sprawdź, czy Docker jest dostępny
	if _, err := exec.LookPath("docker"); err != nil {
		log.Println("Docker nie jest dostępny na tym systemie")
		return services, nil
	}
	
	// Wykonaj komendę Docker
	cmd := exec.Command("docker", "ps", "-a", "--format", "{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}\\t{{.Command}}")
	output, err := cmd.Output()
	if err != nil {
		return services, fmt.Errorf("błąd podczas wykonywania komendy docker: %v", err)
	}
	
	// Parsuj wynik
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		
		fields := strings.Split(line, "\t")
		if len(fields) >= 4 {
			containerId := fields[0]
			containerName := fields[1]
			containerImage := fields[2]
			containerStatus := fields[3]
			
			// Pobierz szczegółowe informacje o kontenerze
			service := models.Service{
				Name:      containerName,
				Type:      "docker",
				ID:        containerId,
				Image:     containerImage,
				Status:    strings.HasPrefix(containerStatus, "Up") ? "running" : "stopped",
				Timestamp: time.Now().Format(time.RFC3339),
			}
			
			// Porty
			if len(fields) >= 5 && fields[4] != "" {
				ports := []map[string]string{}
				portMappings := strings.Split(fields[4], ", ")
				for _, portMapping := range portMappings {
					parts := strings.Split(portMapping, "->")
					if len(parts) == 2 {
						hostPart := strings.Split(parts[0], ":")
						containerPort := parts[1]
						
						portInfo := map[string]string{}
						if len(hostPart) == 2 {
							portInfo["host_ip"] = hostPart[0]
							portInfo["host_port"] = hostPart[1]
						} else {
							portInfo["host_port"] = hostPart[0]
						}
						portInfo["container_port"] = containerPort
						
						ports = append(ports, portInfo)
					}
				}
				service.Ports = ports
			}
			
			// Wykonaj komendę inspect, aby uzyskać więcej informacji
			cmd = exec.Command("docker", "inspect", containerId)
			inspectOutput, err := cmd.Output()
			if err == nil {
				var inspectData []map[string]interface{}
				if err := json.Unmarshal(inspectOutput, &inspectData); err == nil && len(inspectData) > 0 {
					containerData := inspectData[0]
					
					// Wolumeny
					if mounts, ok := containerData["Mounts"].([]interface{}); ok {
						volumes := []map[string]interface{}{}
						for _, mount := range mounts {
							if mountData, ok := mount.(map[string]interface{}); ok {
								volumeInfo := map[string]interface{}{
									"type":        mountData["Type"],
									"source":      mountData["Source"],
									"destination": mountData["Destination"],
									"read_only":   mountData["RO"],
								}
								volumes = append(volumes, volumeInfo)
							}
						}
						service.Volumes = volumes
					}
					
					// Zmienne środowiskowe
					if config, ok := containerData["Config"].(map[string]interface{}); ok {
						if env, ok := config["Env"].([]interface{}); ok {
							envStrings := make([]string, 0, len(env))
							for _, e := range env {
								if envStr, ok := e.(string); ok {
									envStrings = append(envStrings, envStr)
								}
							}
							service.Environment = envStrings
						}
					}
					
					// Sprawdź, czy to kontener z LLM
					isLLM := false
					
					// Sprawdź nazwę obrazu
					imageLower := strings.ToLower(containerImage)
					for _, keyword := range llmKeywords {
						if strings.Contains(imageLower, keyword) {
							isLLM = true
							break
						}
					}
					
					// Sprawdź zmienne środowiskowe
					if len(service.Environment) > 0 {
						envStr := strings.ToLower(strings.Join(service.Environment, " "))
						for _, keyword := range llmKeywords {
							if strings.Contains(envStr, keyword) {
								isLLM = true
								break
							}
						}
					}
					
					service.IsLLMRelated = isLLM
				}
			}
			
			services = append(services, service)
		}
	}
	
	return services, nil
}
