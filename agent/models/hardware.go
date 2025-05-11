# Model informacji o sprzęcie
// agent/models/hardware.go
package models

// Hardware reprezentuje informacje o sprzęcie
type Hardware struct {
	Hostname        string                      `json:"hostname"`
	Platform        string                      `json:"platform"`
	PlatformVersion string                      `json:"platform_version"`
	KernelVersion   string                      `json:"kernel_version"`
	OS              string                      `json:"os"`
	Uptime          uint64                      `json:"uptime"`
	CPU             *CPU                        `json:"cpu"`
	Memory          *Memory                     `json:"memory"`
	Disks           []Disk                      `json:"disks"`
	Network         map[string]NetworkInterface `json:"network"`
	GPU             map[string][]GPUDevice      `json:"gpu,omitempty"`
}

// CPU reprezentuje informacje o procesorze
type CPU struct {
	Model        string     `json:"model"`
	PhysicalCores int        `json:"cores_physical"`
	LogicalCores  int        `json:"count_logical"`
	UsagePercent  float64    `json:"usage_percent"`
	PerCPU        []CPUCore  `json:"per_cpu"`
}

// CPUCore reprezentuje informacje o pojedynczym rdzeniu procesora
type CPUCore struct {
	UsagePercent float64 `json:"usage_percent"`
}

// Memory reprezentuje informacje o pamięci
type Memory struct {
	TotalGB     float64 `json:"total_gb"`
	AvailableGB float64 `json:"available_gb"`
	UsedGB      float64 `json:"used_gb"`
	FreeGB      float64 `json:"free_gb"`
	Percent     float64 `json:"percent"`
	SwapTotalGB float64 `json:"swap_total_gb,omitempty"`
	SwapUsedGB  float64 `json:"swap_used_gb,omitempty"`
	SwapPercent float64 `json:"swap_percent,omitempty"`
}

// Disk reprezentuje informacje o dysku
type Disk struct {
	Device     string  `json:"device"`
	Mountpoint string  `json:"mountpoint"`
	Fstype     string  `json:"fstype"`
	TotalGB    float64 `json:"total_gb"`
	UsedGB     float64 `json:"used_gb"`
	FreeGB     float64 `json:"free_gb"`
	Percent    float64 `json:"percent"`
}

// NetworkInterface reprezentuje informacje o interfejsie sieciowym
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

// GPUDevice reprezentuje informacje o urządzeniu GPU
type GPUDevice struct {
	Index           int     `json:"index"`
	Name            string  `json:"name"`
	Temperature     float64 `json:"temperature"`
	UtilizationGPU  float64 `json:"utilization_percent"`
	MemoryUsedMB    float64 `json:"memory_used_mb"`
	MemoryTotalMB   float64 `json:"memory_total_mb"`
}

