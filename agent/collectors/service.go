package collectors

import (
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/process"
	"github.com/shirou/gopsutil/v3/host"

	"gitlab.com/safetytwin/safetytwin/agent/models"
)

// ServiceCollector zbiera informacje o usługach
type ServiceCollector struct {
	// Lista wyrażeń regularnych dla usług związanych z LLM
	llmPatterns []*regexp.Regexp
}

// NewServiceCollector tworzy nowy kolektor informacji o usługach
func NewServiceCollector() *ServiceCollector {
	// Wzorce dla usług związanych z LLM
	llmPatterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)torch`),
		regexp.MustCompile(`(?i)tensorflow`),
		regexp.MustCompile(`(?i)transformers`),
		regexp.MustCompile(`(?i)huggingface`),
		regexp.MustCompile(`(?i)llama`),
		regexp.MustCompile(`(?i)bert`),
		regexp.MustCompile(`(?i)gpt`),
		regexp.MustCompile(`(?i)t5`),
		regexp.MustCompile(`(?i)whisper`),
		regexp.MustCompile(`(?i)llama.cpp`),
		regexp.MustCompile(`(?i)ggml`),
		regexp.MustCompile(`(?i)ollama`),
		regexp.MustCompile(`(?i)text-generation-server`),
		regexp.MustCompile(`(?i)nvidia-smi`),
		regexp.MustCompile(`(?i)ml`),
		regexp.MustCompile(`(?i)ai`),
		regexp.MustCompile(`(?i)inference`),
		regexp.MustCompile(`(?i)model`),
	}

	return &ServiceCollector{
		llmPatterns: llmPatterns,
	}
}

// Collect zbiera informacje o usługach i zwraca slice wypełnionych obiektów Service
func (c *ServiceCollector) Collect() ([]models.Service, error) {
	// Pobierz nazwę hosta
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "unknown"
	}

	// Utwórz slice na informacje o usługach
	services := make([]models.Service, 0)

	// Zbierz usługi systemowe
	systemServices, err := c.collectSystemServices(hostname)
	if err != nil {
		fmt.Printf("Ostrzeżenie: nie można zebrać informacji o usługach systemowych: %v\n", err)
	} else {
		services = append(services, systemServices...)
	}

	// Zbierz usługi dockerowe
	dockerServices, err := c.collectDockerServices(hostname)
	if err != nil {
		fmt.Printf("Ostrzeżenie: nie można zebrać informacji o usługach dockerowych: %v\n", err)
	} else {
		services = append(services, dockerServices...)
	}

	return services, nil
}

// collectSystemServices zbiera informacje o usługach systemowych
func (c *ServiceCollector) collectSystemServices(hostname string) ([]models.Service, error) {
	// Pobierz listę usług systemowych
	services, err := host.Services()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas pobierania listy usług systemowych: %v", err)
	}

	// Utwórz slice na informacje o usługach
	serviceModels := make([]models.Service, 0, len(services))

	// Aktualny czas
	currentTime := time.Now()
	timestamp := currentTime.Format(time.RFC3339)

	// Zbierz informacje o każdej usłudze
	for _, svc := range services {
		// Utwórz model usługi
		service := models.Service{
			Name:      svc.Name,
			Type:      "system",
			ID:        svc.Name,
			Hostname:  hostname,
			Timestamp: timestamp,
			Status:    c.mapServiceStatus(svc.Status),
		}

		// Pobierz informacje o procesie, jeśli usługa jest uruchomiona
		if svc.Status == "running" && svc.PID > 0 {
			service.PID = svc.PID

			// Pobierz proces
			proc, err := process.NewProcess(svc.PID)
			if err == nil {
				// Pobierz czas utworzenia
				createTime, err := proc.CreateTime()
				if err == nil {
					startTime := time.Unix(createTime/1000, 0)
					service.StartTime = startTime.Format(time.RFC3339)
					service.UptimeSeconds = int64(currentTime.Sub(startTime).Seconds())
				}

				// Pobierz użycie CPU
				cpuPercent, err := proc.CPUPercent()
				if err == nil {
					service.CPUPercent = cpuPercent
				}

				// Pobierz użycie pamięci
				memoryPercent, err := proc.MemoryPercent()
				if err == nil {
					service.MemoryPercent = memoryPercent
				}

				// Pobierz linię poleceń
				cmdline, err := proc.Cmdline()
				if err == nil {
					service.Extra = map[string]interface{}{
						"cmdline": cmdline,
					}
				}

				// Sprawdź, czy usługa jest związana z LLM
				service.IsLLMRelated = c.isLLMRelated(service.Name, cmdline)
			}
		}

		serviceModels = append(serviceModels, service)
	}

	return serviceModels, nil
}

// collectDockerServices zbiera informacje o usługach dockerowych
func (c *ServiceCollector) collectDockerServices(hostname string) ([]models.Service, error) {
	// Tutaj można użyć klienta Docker API do pobrania informacji o kontenerach
	// Dla uproszczenia, użyjemy DockerCollector, jeśli jest dostępny
	// W przeciwnym razie, zwrócimy pustą listę

	// Sprawdź, czy DockerCollector jest dostępny
	dockerCollector := NewDockerCollector()
	if dockerCollector == nil {
		return []models.Service{}, nil
	}

	// Pobierz informacje o kontenerach
	containers, err := dockerCollector.Collect()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas pobierania informacji o kontenerach: %v", err)
	}

	// Utwórz slice na informacje o usługach
	serviceModels := make([]models.Service, 0, len(containers))

	// Aktualny czas
	timestamp := time.Now().Format(time.RFC3339)

	// Konwertuj kontenery na usługi
	for _, container := range containers {
		// Utwórz model usługi
		service := models.Service{
			Name:      container.Name,
			Type:      "docker",
			ID:        container.ID,
			Hostname:  hostname,
			Timestamp: timestamp,
			Status:    container.Status,
			Image:     container.Image,
			Ports:     make([]models.Port, 0),
			Volumes:   make([]models.Volume, 0),
		}

		// Dodaj porty
		for _, port := range container.Ports {
			service.Ports = append(service.Ports, models.Port{
				ContainerPort: port.ContainerPort,
				HostIP:        port.HostIP,
				HostPort:      port.HostPort,
			})
		}

		// Dodaj wolumeny
		for _, volume := range container.Volumes {
			service.Volumes = append(service.Volumes, models.Volume{
				Source:      volume.Source,
				Destination: volume.Destination,
				ReadOnly:    volume.ReadOnly,
				Type:        volume.Type,
			})
		}

		// Dodaj zmienne środowiskowe
		service.Environment = container.Environment

		// Dodaj linki
		service.Links = container.Links

		// Sprawdź, czy usługa jest związana z LLM
		service.IsLLMRelated = c.isLLMRelated(container.Name, container.Image)
		if !service.IsLLMRelated {
			// Sprawdź zmienne środowiskowe
			for _, env := range container.Environment {
				if c.isLLMRelated("", env) {
					service.IsLLMRelated = true
					break
				}
			}
		}

		serviceModels = append(serviceModels, service)
	}

	return serviceModels, nil
}

// mapServiceStatus mapuje status usługi na standardowy format
func (c *ServiceCollector) mapServiceStatus(status string) string {
	switch strings.ToLower(status) {
	case "running":
		return "running"
	case "stopped", "stop":
		return "stopped"
	case "starting":
		return "starting"
	case "stopping":
		return "stopping"
	case "paused":
		return "paused"
	case "exited":
		return "exited"
	case "dead":
		return "dead"
	default:
		return status
	}
}

// isLLMRelated sprawdza, czy usługa jest związana z LLM
func (c *ServiceCollector) isLLMRelated(name, description string) bool {
	// Sprawdź nazwę
	for _, pattern := range c.llmPatterns {
		if pattern.MatchString(name) {
			return true
		}
	}

	// Sprawdź opis
	if description != "" {
		for _, pattern := range c.llmPatterns {
			if pattern.MatchString(description) {
				return true
			}
		}
	}

	return false
}
