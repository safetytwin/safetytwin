package models

// SystemState reprezentuje stan systemu
type SystemState struct {
	Hostname  string      `json:"hostname"`
	Timestamp int64       `json:"timestamp"`
	CPU       *CPUInfo    `json:"cpu,omitempty"`
	Memory    *MemoryInfo `json:"memory,omitempty"`
	Disks     []*DiskInfo `json:"disks,omitempty"`
	Network   *NetInfo    `json:"network,omitempty"`
	Processes []*Process  `json:"processes,omitempty"`
}

// CPUInfo zawiera informacje o CPU
type CPUInfo struct {
	Usage       float64 `json:"usage"`
	Temperature float64 `json:"temperature,omitempty"`
	Cores       int     `json:"cores"`
}

// MemoryInfo zawiera informacje o pamięci
type MemoryInfo struct {
	Total     uint64  `json:"total"`
	Used      uint64  `json:"used"`
	Available uint64  `json:"available"`
	UsagePerc float64 `json:"usage_perc"`
}

// DiskInfo zawiera informacje o dysku
type DiskInfo struct {
	Device    string  `json:"device"`
	MountPath string  `json:"mount_path"`
	Total     uint64  `json:"total"`
	Used      uint64  `json:"used"`
	Available uint64  `json:"available"`
	UsagePerc float64 `json:"usage_perc"`
}

// NetInfo zawiera informacje o sieci
type NetInfo struct {
	Interfaces []*NetInterface `json:"interfaces"`
}

// NetInterface zawiera informacje o interfejsie sieciowym
type NetInterface struct {
	Name       string   `json:"name"`
	MACAddress string   `json:"mac_address"`
	IPAddrs    []string `json:"ip_addresses"`
	BytesSent  uint64   `json:"bytes_sent"`
	BytesRecv  uint64   `json:"bytes_recv"`
}

// Process zawiera informacje o procesie
type Process struct {
	PID        int32   `json:"pid"`
	Name       string  `json:"name"`
	Username   string  `json:"username"`
	CPUUsage   float64 `json:"cpu_usage"`
	MemoryUsed uint64  `json:"memory_used"`
	Status     string  `json:"status"`
	Command    string  `json:"command,omitempty"`
}
