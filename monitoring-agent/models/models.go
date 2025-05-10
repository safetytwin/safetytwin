package models

// SystemState przechowuje kompletny stan systemu
type SystemState struct {
	Timestamp string     `json:"timestamp"`
	Hardware  *Hardware  `json:"hardware"`
	Services  []Service  `json:"services"`
	Processes []Process  `json:"processes,omitempty"`
}

// Hardware przechowuje informacje o sprzęcie komputerowym
type Hardware struct {
	Hostname        string                    `json:"hostname"`
	Platform        string                    `json:"platform"`
	PlatformVersion string                    `json:"platform_version"`
	KernelVersion   string                    `json:"kernel_version"`
	OS              string                    `json:"os"`
	Uptime          uint64                    `json:"uptime"`
	CPU             *CPU                      `json:"cpu"`
	Memory          *Memory                   `json:"memory"`
	Disks           []Disk                    `json:"disks"`
	Network         map[string]NetworkInterface `json:"network"`
}

// CPU przechowuje informacje o procesorze
type CPU struct {
	Model         string    `json:"model"`
	PhysicalCores int32     `json:"physical_cores"`
	LogicalCores  int       `json:"logical_cores"`
	UsagePercent  float64   `json:"usage_percent"`
	PerCPU        []CPUCore `json:"per_cpu"`
}

// CPUCore przechowuje informacje o pojedynczym rdzeniu CPU
type CPUCore struct {
	UsagePercent float64 `json:"usage_percent"`
}

// Memory przechowuje informacje o pamięci
type Memory struct {
	TotalGB     float64 `json:"total_gb"`
	AvailableGB float64 `json:"available_gb"`
	UsedGB      float64 `json:"used_gb"`
	FreeGB      float64 `json:"free_gb"`
	Percent     float64 `json:"percent"`
	SwapTotalGB float64 `json:"swap_total_gb"`
	SwapUsedGB  float64 `json:"swap_used_gb"`
	SwapPercent float64 `json:"swap_percent"`
}

// Disk przechowuje informacje o dysku
type Disk struct {
	Device     string  `json:"device"`
	Mountpoint string  `json:"mountpoint"`
	Fstype     string  `json:"fstype"`
	TotalGB    float64 `json:"total_gb"`
	UsedGB     float64 `json:"used_gb"`
	FreeGB     float64 `json:"free_gb"`
	Percent    float64 `json:"percent"`
}

// NetworkInterface przechowuje informacje o interfejsie sieciowym
type NetworkInterface struct {
	Name        string   `json:"name"`
	MAC         string   `json:"mac"`
	Addresses   []string `json:"addresses"`
	Flags       string   `json:"flags"`
	BytesSent   uint64   `json:"bytes_sent,omitempty"`
	BytesRecv   uint64   `json:"bytes_recv,omitempty"`
	PacketsSent uint64   `json:"packets_sent,omitempty"`
	PacketsRecv uint64   `json:"packets_recv,omitempty"`
	Errin       uint64   `json:"errin,omitempty"`
	Errout      uint64   `json:"errout,omitempty"`
	Dropin      uint64   `json:"dropin,omitempty"`
	Dropout     uint64   `json:"dropout,omitempty"`
}

// Service przechowuje informacje o usłudze
type Service struct {
	Name      string `json:"name"`
	Type      string `json:"type"` // systemd, docker, etc.
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
	PID       int    `json:"pid,omitempty"`
	// Dodatkowe pola dla kontenerów Docker
	Image         string              `json:"image,omitempty"`
	ID            string              `json:"id,omitempty"`
	Ports         []map[string]string `json:"ports,omitempty"`
	Volumes       []map[string]interface{} `json:"volumes,omitempty"`
	Environment   []string            `json:"environment,omitempty"`
	IsLLMRelated  bool                `json:"is_llm_related,omitempty"`
}

// Process przechowuje informacje o procesie
type Process struct {
	PID           int32                  `json:"pid"`
	Name          string                 `json:"name"`
	Cmdline       []string               `json:"cmdline,omitempty"`
	Status        string                 `json:"status,omitempty"`
	Username      string                 `json:"username,omitempty"`
	CreateTime    string                 `json:"create_time,omitempty"`
	CPUPercent    float64                `json:"cpu_percent,omitempty"`
	MemoryPercent float32                `json:"memory_percent,omitempty"`
	MemoryInfo    map[string]uint64      `json:"memory_info,omitempty"`
	NumThreads    int32                  `json:"num_threads,omitempty"`
	Cwd           string                 `json:"cwd,omitempty"`
	IsLLMRelated  bool                   `json:"is_llm_related"`
	OpenFiles     []map[string]interface{} `json:"open_files,omitempty"`
	Connections   []map[string]interface{} `json:"connections,omitempty"`
	IOCounters    map[string]interface{} `json:"io_counters,omitempty"`
}
