package collectors

import (
	"context"
	"fmt"
	"strings"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"

	"gitlab.com/safetytwin/safetytwin/agent/models"
)

// DockerContainer reprezentuje informacje o kontenerze Docker
type DockerContainer struct {
	ID          string
	Name        string
	Image       string
	Status      string
	Ports       []models.Port
	Volumes     []models.Volume
	Environment []string
	Links       []string
}

// DockerCollector zbiera informacje o kontenerach Docker
type DockerCollector struct {
	client *client.Client
}

// NewDockerCollector tworzy nowy kolektor informacji o kontenerach Docker
func NewDockerCollector() *DockerCollector {
	// Inicjalizuj klienta Docker
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		// Jeśli nie można zainicjować klienta, zwróć nil
		fmt.Printf("Ostrzeżenie: nie można zainicjować klienta Docker: %v\n", err)
		return nil
	}

	return &DockerCollector{
		client: cli,
	}
}

// Collect zbiera informacje o kontenerach Docker
func (c *DockerCollector) Collect() ([]DockerContainer, error) {
	// Utwórz kontekst
	ctx := context.Background()

	// Pobierz listę kontenerów
	containers, err := c.client.ContainerList(ctx, container.ListOptions{All: true})
	if err != nil {
		return nil, fmt.Errorf("błąd podczas pobierania listy kontenerów: %v", err)
	}

	// Utwórz slice na informacje o kontenerach
	containerModels := make([]DockerContainer, 0, len(containers))

	// Zbierz informacje o każdym kontenerze
	for _, cont := range containers {
		// Pobierz szczegółowe informacje o kontenerze
		contInfo, err := c.client.ContainerInspect(ctx, cont.ID)
		if err != nil {
			fmt.Printf("Ostrzeżenie: nie można pobrać szczegółowych informacji o kontenerze %s: %v\n", cont.ID, err)
			continue
		}

		// Utwórz model kontenera
		container := DockerContainer{
			ID:     cont.ID,
			Name:   strings.TrimPrefix(contInfo.Name, "/"),
			Image:  cont.Image,
			Status: cont.State,
		}

		// Zbierz informacje o portach
		container.Ports = c.collectPorts(cont.Ports)

		// Zbierz informacje o wolumenach
		container.Volumes = c.collectVolumes(contInfo.Mounts)

		// Zbierz zmienne środowiskowe
		container.Environment = contInfo.Config.Env

		// Zbierz linki
		container.Links = c.collectLinks(contInfo.HostConfig.Links)

		containerModels = append(containerModels, container)
	}

	return containerModels, nil
}

// collectPorts zbiera informacje o portach kontenera
func (c *DockerCollector) collectPorts(ports []types.Port) []models.Port {
	portModels := make([]models.Port, 0, len(ports))

	for _, port := range ports {
		portModel := models.Port{
			ContainerPort: fmt.Sprintf("%d/%s", port.PrivatePort, port.Type),
			HostIP:        port.IP,
			HostPort:      fmt.Sprintf("%d", port.PublicPort),
		}

		portModels = append(portModels, portModel)
	}

	return portModels
}

// collectVolumes zbiera informacje o wolumenach kontenera
func (c *DockerCollector) collectVolumes(mounts []types.MountPoint) []models.Volume {
	volumeModels := make([]models.Volume, 0, len(mounts))

	for _, mount := range mounts {
		volumeModel := models.Volume{
			Source:      mount.Source,
			Destination: mount.Destination,
			ReadOnly:    mount.RW,
			Type:        string(mount.Type),
		}

		volumeModels = append(volumeModels, volumeModel)
	}

	return volumeModels
}

// collectLinks zbiera informacje o linkach kontenera
func (c *DockerCollector) collectLinks(links []string) []string {
	// Zwracamy kopię slice, aby uniknąć modyfikacji oryginalnych danych
	if links == nil {
		return []string{}
	}

	linksCopy := make([]string, len(links))
	copy(linksCopy, links)

	return linksCopy
}
