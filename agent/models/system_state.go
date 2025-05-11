# Model stanu systemu

// agent/models/system_state.go
package models

import (
	"time"
)

// SystemState reprezentuje pełny stan monitorowanego systemu
type SystemState struct {
	Timestamp string     `json:"timestamp"`
	Hardware  *Hardware  `json:"hardware"`
	Services  []Service  `json:"services"`
	Processes []Process  `json:"processes"`
}

// NewSystemState tworzy nowy obiekt stanu systemu
func NewSystemState() *SystemState {
	return &SystemState{
		Timestamp: time.Now().Format(time.RFC3339),
		Hardware:  &Hardware{},
		Services:  make([]Service, 0),
		Processes: make([]Process, 0),
	}
}

