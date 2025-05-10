package collectors

import (
	"fmt"
	"time"

	"gitlab.com/safetytwin/safetytwin/agent/models"
)

// SystemCollector zbiera informacje o całym systemie
type SystemCollector struct {
	hardwareCollector *HardwareCollector
	processCollector  *ProcessCollector
	serviceCollector  *ServiceCollector
}

// NewSystemCollector tworzy nowy kolektor informacji o systemie
func NewSystemCollector() *SystemCollector {
	return &SystemCollector{
		hardwareCollector: NewHardwareCollector(),
		processCollector:  NewProcessCollector(),
		serviceCollector:  NewServiceCollector(),
	}
}

// Collect zbiera informacje o systemie i zwraca wypełniony obiekt SystemState
func (c *SystemCollector) Collect() (*models.SystemState, error) {
	// Utwórz nowy obiekt stanu systemu
	systemState := models.NewSystemState()

	// Zbierz informacje o sprzęcie
	fmt.Println("Zbieranie informacji o sprzęcie...")
	hardware, err := c.hardwareCollector.Collect()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o sprzęcie: %v", err)
	}
	systemState.Hardware = hardware

	// Zbierz informacje o procesach
	fmt.Println("Zbieranie informacji o procesach...")
	processes, err := c.processCollector.Collect()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o procesach: %v", err)
	}
	systemState.Processes = processes

	// Zbierz informacje o usługach
	fmt.Println("Zbieranie informacji o usługach...")
	services, err := c.serviceCollector.Collect()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o usługach: %v", err)
	}
	systemState.Services = services

	// Aktualizuj timestamp
	systemState.Timestamp = time.Now().Format(time.RFC3339)

	return systemState, nil
}
