package collectors

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/process"

	"gitlab.com/safetytwin/safetytwin/agent/models"
)

// ProcessCollector zbiera informacje o procesach
type ProcessCollector struct {
	// Lista wyrażeń regularnych dla procesów związanych z LLM
	llmPatterns []*regexp.Regexp
}

// NewProcessCollector tworzy nowy kolektor informacji o procesach
func NewProcessCollector() *ProcessCollector {
	// Wzorce dla procesów związanych z LLM
	llmPatterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)python.*torch`),
		regexp.MustCompile(`(?i)python.*tensorflow`),
		regexp.MustCompile(`(?i)python.*transformers`),
		regexp.MustCompile(`(?i)python.*huggingface`),
		regexp.MustCompile(`(?i)python.*llama`),
		regexp.MustCompile(`(?i)python.*bert`),
		regexp.MustCompile(`(?i)python.*gpt`),
		regexp.MustCompile(`(?i)python.*t5`),
		regexp.MustCompile(`(?i)python.*whisper`),
		regexp.MustCompile(`(?i)llama.cpp`),
		regexp.MustCompile(`(?i)ggml`),
		regexp.MustCompile(`(?i)ollama`),
		regexp.MustCompile(`(?i)text-generation-server`),
		regexp.MustCompile(`(?i)nvidia-smi`),
	}

	return &ProcessCollector{
		llmPatterns: llmPatterns,
	}
}

// Collect zbiera informacje o procesach i zwraca slice wypełnionych obiektów Process
func (c *ProcessCollector) Collect() ([]models.Process, error) {
	// Pobierz listę wszystkich procesów
	processes, err := process.Processes()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas pobierania listy procesów: %v", err)
	}

	// Utwórz slice na informacje o procesach
	processModels := make([]models.Process, 0, len(processes))

	// Zbierz informacje o każdym procesie
	for _, proc := range processes {
		// Pobierz podstawowe informacje o procesie
		processModel, err := c.collectProcessInfo(proc)
		if err != nil {
			// Loguj błąd, ale kontynuuj dla innych procesów
			fmt.Printf("Ostrzeżenie: nie można zebrać informacji o procesie %d: %v\n", proc.Pid, err)
			continue
		}

		// Sprawdź, czy proces jest związany z LLM
		processModel.IsLLMRelated = c.isLLMRelated(processModel)

		// Dodaj do listy
		processModels = append(processModels, *processModel)
	}

	return processModels, nil
}

// collectProcessInfo zbiera informacje o pojedynczym procesie
func (c *ProcessCollector) collectProcessInfo(proc *process.Process) (*models.Process, error) {
	// Utwórz nowy model procesu
	processModel := &models.Process{
		PID: proc.Pid,
	}

	// Pobierz nazwę procesu
	name, err := proc.Name()
	if err == nil {
		processModel.Name = name
	} else {
		processModel.Name = "unknown"
	}

	// Pobierz PPID
	ppid, err := proc.Ppid()
	if err == nil {
		processModel.PPID = ppid
	}

	// Pobierz nazwę użytkownika
	username, err := proc.Username()
	if err == nil {
		processModel.Username = username
	} else {
		processModel.Username = "unknown"
	}

	// Pobierz status
	status, err := proc.Status()
	if err == nil && len(status) > 0 {
		processModel.Status = status[0]
	} else {
		processModel.Status = "unknown"
	}

	// Pobierz czas utworzenia
	createTime, err := proc.CreateTime()
	if err == nil {
		// Konwertuj timestamp na string w formacie RFC3339
		processModel.CreateTime = time.Unix(createTime/1000, 0).Format(time.RFC3339)
	} else {
		processModel.CreateTime = time.Now().Format(time.RFC3339)
	}

	// Pobierz użycie CPU
	cpuPercent, err := proc.CPUPercent()
	if err == nil {
		processModel.CPUPercent = cpuPercent
	}

	// Pobierz użycie pamięci
	memoryPercent, err := proc.MemoryPercent()
	if err == nil {
		processModel.MemoryPercent = memoryPercent
	}

	// Pobierz informacje o pamięci
	memoryInfo, err := proc.MemoryInfo()
	if err == nil {
		processModel.MemoryInfo = &models.MemoryInfo{
			RSS: memoryInfo.RSS,
			VMS: memoryInfo.VMS,
		}
	} else {
		processModel.MemoryInfo = &models.MemoryInfo{}
	}

	// Pobierz linię poleceń
	cmdline, err := proc.Cmdline()
	if err == nil {
		// Podziel na argumenty
		processModel.Cmdline = strings.Fields(cmdline)
	} else {
		processModel.Cmdline = []string{}
	}

	// Pobierz katalog roboczy
	cwd, err := proc.Cwd()
	if err == nil {
		processModel.CWD = cwd
	}

	// Pobierz zmienne środowiskowe (może być niedostępne dla niektórych procesów)
	env, err := proc.Environ()
	if err == nil {
		processModel.Environment = env
	}

	// Pobierz liczbę wątków
	numThreads, err := proc.NumThreads()
	if err == nil {
		processModel.NumThreads = numThreads
	}

	// Pobierz otwarte pliki (może być niedostępne dla niektórych procesów)
	openFiles, err := proc.OpenFiles()
	if err == nil {
		files := make([]models.OpenFile, 0, len(openFiles))
		for _, file := range openFiles {
			openFile := models.OpenFile{
				Path: file.Path,
				FD:   file.Fd,
			}
			files = append(files, openFile)
		}
		processModel.OpenFiles = files
	}

	// Pobierz połączenia sieciowe (może być niedostępne dla niektórych procesów)
	connections, err := proc.Connections()
	if err == nil {
		conns := make([]models.Connection, 0, len(connections))
		for _, conn := range connections {
			connection := models.Connection{
				FD:     conn.Fd,
				Family: c.getConnectionFamily(conn.Family),
				Type:   c.getConnectionType(conn.Type),
				Status: c.getConnectionStatus(conn.Status),
				LocalAddress: &models.SocketAddress{
					IP:   conn.Laddr.IP,
					Port: conn.Laddr.Port,
				},
			}

			// Dodaj adres zdalny, jeśli istnieje
			if conn.Raddr.IP != "" {
				connection.RemoteAddress = &models.SocketAddress{
					IP:   conn.Raddr.IP,
					Port: conn.Raddr.Port,
				}
			}

			conns = append(conns, connection)
		}
		processModel.Connections = conns
	}

	// Pobierz liczniki I/O (może być niedostępne dla niektórych procesów)
	ioCounters, err := proc.IOCounters()
	if err == nil {
		processModel.IOCounters = &models.IOCounters{
			ReadCount:  ioCounters.ReadCount,
			WriteCount: ioCounters.WriteCount,
			ReadBytes:  ioCounters.ReadBytes,
			WriteBytes: ioCounters.WriteBytes,
		}
	}

	return processModel, nil
}

// isLLMRelated sprawdza, czy proces jest związany z LLM
func (c *ProcessCollector) isLLMRelated(proc *models.Process) bool {
	// Sprawdź nazwę procesu
	for _, pattern := range c.llmPatterns {
		if pattern.MatchString(proc.Name) {
			return true
		}
	}

	// Sprawdź linię poleceń
	cmdline := strings.Join(proc.Cmdline, " ")
	for _, pattern := range c.llmPatterns {
		if pattern.MatchString(cmdline) {
			return true
		}
	}

	// Sprawdź otwarte pliki pod kątem modeli LLM
	for _, file := range proc.OpenFiles {
		filename := filepath.Base(file.Path)
		if strings.Contains(strings.ToLower(filename), "model") &&
			(strings.HasSuffix(strings.ToLower(filename), ".bin") ||
				strings.HasSuffix(strings.ToLower(filename), ".gguf") ||
				strings.HasSuffix(strings.ToLower(filename), ".ggml") ||
				strings.HasSuffix(strings.ToLower(filename), ".pt") ||
				strings.HasSuffix(strings.ToLower(filename), ".pth") ||
				strings.HasSuffix(strings.ToLower(filename), ".safetensors")) {
			return true
		}
	}

	return false
}

// getConnectionFamily zwraca rodzinę połączenia jako string
func (c *ProcessCollector) getConnectionFamily(family uint32) string {
	switch family {
	case 1:
		return "unix"
	case 2:
		return "ipv4"
	case 10:
		return "ipv6"
	default:
		return fmt.Sprintf("unknown(%d)", family)
	}
}

// getConnectionType zwraca typ połączenia jako string
func (c *ProcessCollector) getConnectionType(connType uint32) string {
	switch connType {
	case 1:
		return "tcp"
	case 2:
		return "udp"
	case 3:
		return "raw"
	default:
		return fmt.Sprintf("unknown(%d)", connType)
	}
}

// getConnectionStatus zwraca status połączenia jako string
func (c *ProcessCollector) getConnectionStatus(status uint32) string {
	statusMap := map[uint32]string{
		1:  "established",
		2:  "syn_sent",
		3:  "syn_recv",
		4:  "fin_wait1",
		5:  "fin_wait2",
		6:  "time_wait",
		7:  "close",
		8:  "close_wait",
		9:  "last_ack",
		10: "listen",
		11: "closing",
	}

	if status, ok := statusMap[status]; ok {
		return status
	}
	return fmt.Sprintf("unknown(%d)", status)
}
