# Model informacji o procesach

// agent/models/process.go
package models

// Process reprezentuje informacje o procesie
type Process struct {
	PID           int32                  `json:"pid"`
	PPID          int32                  `json:"ppid,omitempty"`
	Name          string                 `json:"name"`
	Username      string                 `json:"username"`
	Status        string                 `json:"status"`
	CreateTime    string                 `json:"create_time"`
	CPUPercent    float64                `json:"cpu_percent"`
	MemoryPercent float32                `json:"memory_percent"`
	MemoryInfo    *MemoryInfo            `json:"memory_info"`
	Cmdline       []string               `json:"cmdline"`
	CWD           string                 `json:"cwd,omitempty"`
	Environment   []string               `json:"environment,omitempty"`
	NumThreads    int32                  `json:"num_threads"`
	OpenFiles     []OpenFile             `json:"open_files,omitempty"`
	Connections   []Connection           `json:"connections,omitempty"`
	IOCounters    *IOCounters            `json:"io_counters,omitempty"`
	IsLLMRelated  bool                   `json:"is_llm_related"`
	Extra         map[string]interface{} `json:"extra,omitempty"`
}

// MemoryInfo reprezentuje informacje o pamięci procesu
type MemoryInfo struct {
	RSS     uint64 `json:"rss"`  // Resident Set Size
	VMS     uint64 `json:"vms"`  // Virtual Memory Size
	Shared  uint64 `json:"shared,omitempty"`
	Text    uint64 `json:"text,omitempty"`
	Data    uint64 `json:"data,omitempty"`
	Swap    uint64 `json:"swap,omitempty"`
}

// OpenFile reprezentuje otwarty plik
type OpenFile struct {
	Path     string `json:"path"`
	FD       uint64 `json:"fd"`
	Position uint64 `json:"position,omitempty"`
	Mode     string `json:"mode,omitempty"`
	Flags    int    `json:"flags,omitempty"`
}

// Connection reprezentuje połączenie sieciowe
type Connection struct {
	FD            int32           `json:"fd"`
	Family        string          `json:"family"`
	Type          string          `json:"type"`
	LocalAddress  *SocketAddress  `json:"local_address"`
	RemoteAddress *SocketAddress  `json:"remote_address,omitempty"`
	Status        string          `json:"status"`
}

// SocketAddress reprezentuje adres dla połączenia sieciowego
type SocketAddress struct {
	IP   string `json:"ip"`
	Port uint32 `json:"port"`
}

// IOCounters reprezentuje liczniki I/O dla procesu
type IOCounters struct {
	ReadCount  uint64 `json:"read_count"`
	WriteCount uint64 `json:"write_count"`
	ReadBytes  uint64 `json:"read_bytes"`
	WriteBytes uint64 `json:"write_bytes"`
}

