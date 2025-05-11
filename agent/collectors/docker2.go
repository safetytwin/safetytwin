package collectors

import (
	"context"
	"safetytwin/agent/models"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
)

// CollectDockerContainers zbiera informacje o kontenerach Docker
func CollectDockerContainers() ([]models.Service, error) {
	// Sprawdź, czy Docker jest dostępny
	if _, err := exec.LookPath("docker"); err != nil {
		return nil, fmt.Errorf("docker nie jest dostępny: %v", err)
	}

	// Utwórz klienta Docker
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, fmt.Errorf("nie można utworzyć klienta Docker: %v", err)
	}
	defer cli.Close()

	// Pobierz listę kontenerów
	containers, err := cli.ContainerList(context.Background(), container.ListOptions{All: true})
	if err != nil {
		return nil, fmt.Errorf("nie można pobrać listy kontenerów: %v", err)
	}

	// Utwórz listę usług
	services := make([]models.Service, 0, len(containers))
	hostname, _ := getHostname()

	// Iteruj przez kontenery
	for _, c := range containers {
		// Podstawowe informacje o kontenerze
		service := models.Service{
			Name:      c.Names[0][1:], // Usuń początkowy znak "/"
			Type:      "docker",
			ID:        c.ID,
			Hostname:  hostname,
			Timestamp: time.Now().Format(time.RFC3339),
			Status:    "running",
			Image:     c.Image,
		}

		// Sprawdź stan kontenera
		if c.State != "running" {
			service.Status = c.State
		}

		// Pobierz szczegółowe informacje o kontenerze
		containerInfo, err := cli.ContainerInspect(context.Background(), c.ID)
		if err != nil {
			continue
		}

		// Czas uruchomienia
		if containerInfo.State.StartedAt != "" {
			startTime, err := time.Parse(time.RFC3339Nano, containerInfo.State.StartedAt)
			if err == nil {
				service.StartTime = startTime.Format(time.RFC3339)
				service.UptimeSeconds = int64(time.Since(startTime).Seconds())
			}
		}

		// PID
		if containerInfo.State.Pid > 0 {
			service.PID = int32(containerInfo.State.Pid)
		}

		// Porty
		service.Ports = make([]models.Port, 0, len(c.Ports))
		for _, p := range c.Ports {
			port := models.Port{
				ContainerPort: fmt.Sprintf("%d/%s", p.PrivatePort, p.Type),
				HostIP:        p.IP,
				HostPort:      fmt.Sprintf("%d", p.PublicPort),
			}
			service.Ports = append(service.Ports, port)
		}

		// Wolumeny
		service.Volumes = make([]models.Volume, 0, len(containerInfo.Mounts))
		for _, m := range containerInfo.Mounts {
			volume := models.Volume{
				Source:      m.Source,
				Destination: m.Destination,
				ReadOnly:    m.RW == false,
				Type:        string(m.Type),
			}
			service.Volumes = append(service.Volumes, volume)
		}

		// Zmienne środowiskowe
		if containerInfo.Config != nil && containerInfo.Config.Env != nil {
			service.Environment = containerInfo.Config.Env
		}

		// Powiązania (links)
		if containerInfo.HostConfig != nil && containerInfo.HostConfig.Links != nil {
			service.Links = containerInfo.HostConfig.Links
		}

		// Sprawdź, czy kontener jest związany z LLM
		service.IsLLMRelated = isLLMContainer(containerInfo)

		// Dodaj statystyki (jeśli kontener działa)
		if service.Status == "running" {
			addContainerStats(cli, &service)
		}

		// Dodaj usługę do listy
		services = append(services, service)
	}

	return services, nil
}

// addContainerStats dodaje statystyki do kontenera
func addContainerStats(cli *client.Client, service *models.Service) {
	// Pobierz statystyki
	stats, err := cli.ContainerStats(context.Background(), service.ID, false)
	if err != nil {
		return
	}
	defer stats.Body.Close()

	// Dekoduj statystyki
	var statsData types.StatsJSON
	if err := json.NewDecoder(stats.Body).Decode(&statsData); err != nil {
		return
	}

	// Oblicz wykorzystanie CPU
	cpuDelta := float64(statsData.CPUStats.CPUUsage.TotalUsage - statsData.PreCPUStats.CPUUsage.TotalUsage)
	systemCPUDelta := float64(statsData.CPUStats.SystemCPUUsage - statsData.PreCPUStats.SystemCPUUsage)
	numCPUs := float64(statsData.CPUStats.OnlineCPUs)
	if numCPUs == 0 {
		numCPUs = float64(len(statsData.CPUStats.CPUUsage.PercpuUsage))
	}

	var cpuPercent float64 = 0
	if systemCPUDelta > 0 && cpuDelta > 0 {
		cpuPercent = (cpuDelta / systemCPUDelta) * numCPUs * 100.0
	}
	service.CPUPercent = cpuPercent

	// Oblicz wykorzystanie pamięci
	memoryUsage := float64(statsData.MemoryStats.Usage)
	memoryLimit := float64(statsData.MemoryStats.Limit)
	memoryPercent := (memoryUsage / memoryLimit) * 100.0
	service.MemoryPercent = float32(memoryPercent)

	// Dodaj informacje do pola Extra
	service.Extra = map[string]interface{}{
		"memory_usage_bytes": statsData.MemoryStats.Usage,
		"memory_limit_bytes": statsData.MemoryStats.Limit,
		"network_stats": statsData.Networks,
	}
}

// isLLMContainer sprawdza, czy kontener jest potencjalnie związany z LLM
func isLLMContainer(containerInfo types.ContainerJSON) bool {
	// Lista kluczowych słów dla LLM
	keywords := []string{
		"llama", "gpt", "bert", "transformer", "pytorch", "tensorflow",
		"onnxruntime", "huggingface", "langchain", "llm", "openai",
		"mistral", "vicuna", "falcon",
	}

	// Sprawdź nazwę obrazu
	image := strings.ToLower(containerInfo.Config.Image)
	for _, keyword := range keywords {
		if strings.Contains(image, keyword) {
			return true
		}
	}

	// Sprawdź zmienne środowiskowe
	if containerInfo.Config != nil && containerInfo.Config.Env != nil {
		envStr := strings.ToLower(strings.Join(containerInfo.Config.Env, " "))
		for _, keyword := range keywords {
			if strings.Contains(envStr, keyword) {
				return true
			}
		}
	}

	// Sprawdź etykiety
	if containerInfo.Config != nil && containerInfo.Config.Labels != nil {
		labelsStr := fmt.Sprintf("%v", containerInfo.Config.Labels)
		labelsStr = strings.ToLower(labelsStr)
		for _, keyword := range keywords {
			if strings.Contains(labelsStr, keyword) {
				return true
			}
		}
	}

	return false
}

// GetContainerStats pobiera statystyki dla konkretnego kontenera
func GetContainerStats(containerID string) (*types.StatsJSON, error) {
	// Utwórz klienta Docker
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, fmt.Errorf("nie można utworzyć klienta Docker: %v", err)
	}
	defer cli.Close()

	// Pobierz statystyki
	stats, err := cli.ContainerStats(context.Background(), containerID, false)
	if err != nil {
		return nil, fmt.Errorf("nie można pobrać statystyk: %v", err)
	}
	defer stats.Body.Close()

	// Dekoduj statystyki
	var statsData types.StatsJSON
	if err := json.NewDecoder(stats.Body).Decode(&statsData); err != nil {
		return nil, fmt.Errorf("nie można zdekodować statystyk: %v", err)
	}

	return &statsData, nil
}

// ListRunningContainers zwraca listę działających kontenerów
func ListRunningContainers() ([]types.Container, error) {
	// Utwórz klienta Docker
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, fmt.Errorf("nie można utworzyć klienta Docker: %v", err)
	}
	defer cli.Close()

	// Utwórz filtr dla kontenerów w stanie "running"
	filter := filters.NewArgs()
	filter.Add("status", "running")

	// Pobierz listę kontenerów
	return cli.ContainerList(context.Background(), container.ListOptions{
		Filters: filter,
	})
}