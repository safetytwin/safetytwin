# Model informacji o usługach

// agent/models/service.go
package models

// Service reprezentuje informacje o usłudze
type Service struct {
	Name         string                 `json:"name"`
	Type         string                 `json:"type"`
	ID           string                 `json:"id,omitempty"`
	Hostname     string                 `json:"hostname"`
	Timestamp    string                 `json:"timestamp"`
	Status       string                 `json:"status"`
	PID          int32                  `json:"pid,omitempty"`
	StartTime    string                 `json:"start_time,omitempty"`
	UptimeSeconds int64                 `json:"uptime_seconds,omitempty"`
	CPUPercent   float64                `json:"cpu_percent,omitempty"`
	MemoryPercent float32               `json:"memory_percent,omitempty"`
	Image        string                 `json:"image,omitempty"`
	Ports        []Port                 `json:"ports,omitempty"`
	Volumes      []Volume               `json:"volumes,omitempty"`
	Environment  []string               `json:"environment,omitempty"`
	Links        []string               `json:"links,omitempty"`
	IsLLMRelated bool                   `json:"is_llm_related"`
	Extra        map[string]interface{} `json:"extra,omitempty"`
}

// Port reprezentuje mapowanie portów dla usługi
type Port struct {
	ContainerPort string `json:"container_port"`
	HostIP        string `json:"host_ip,omitempty"`
	HostPort      string `json:"host_port"`
}

// Volume reprezentuje wolumen dla usługi
type Volume struct {
	Source      string `json:"source"`
	Destination string `json:"destination"`
	ReadOnly    bool   `json:"read_only"`
	Type        string `json:"type,omitempty"`
}