package collectors

import (
	"safetytwin/agent/models"
	"fmt"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/process"
)

// Lista słów kluczowych do identyfikacji procesów LLM
var llmKeywords = []string{
	"python", "python3", "llama", "gpt", "bert", "transformer",
	"pytorch", "tensorflow", "onnxruntime", "huggingface",
	"langchain", "llm", "openai", "mistral", "vicuna", "falcon",
}

// CollectProcessesInfo zbiera informacje o procesach systemowych
func CollectProcessesInfo() ([]models.Process, error) {
	// Pobierz wszystkie procesy
	procs, err := process.Processes()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas pobierania listy procesów: %v", err)
	}

	// Utwórz listę procesów
	processes := make([]models.Process, 0, len(procs))
	hostname, _ := getHostname()

	// Iteruj przez procesy
	for _, proc := range procs {
		// Podstawowe informacje
		pid := proc.Pid

		// Sprawdź, czy proces jeszcze istnieje
		if !processExists(proc) {
			continue
		}

		// Nazwa procesu
		name, err := proc.Name()
		if err != nil {
			continue // Pomijamy procesy, dla których nie można uzyskać nazwy
		}

		// Zbierz podstawowe informacje o procesie
		processInfo := models.Process{
			PID:       int32(pid),
			Name:      name,
			Hostname:  hostname,
			Timestamp: time.Now().Format(time.RFC3339),
		}

		// Status
		status, err := proc.Status()
		if err == nil {
			processInfo.Status = status
		}

		// Użytkownik
		username, err := proc.Username()
		if err == nil {
			processInfo.Username = username
		}

		// Czas utworzenia
		createTime, err := proc.CreateTime()
		if err == nil {
			processInfo.CreateTime = time.Unix(createTime/1000, 0).Format(time.RFC3339)
		}

		// Wykorzystanie CPU
		cpuPercent, err := proc.CPUPercent()
		if err == nil {
			processInfo.CPUPercent = cpuPercent
		}

		// Wykorzystanie pamięci
		memPercent, err := proc.MemoryPercent()
		if err == nil {
			processInfo.MemoryPercent = memPercent
		}

		// Informacje o pamięci
		memInfo, err := proc.MemoryInfo()
		if err == nil {
			processInfo.MemoryInfo = &models.MemoryInfo{
				RSS:  memInfo.RSS,
				VMS:  memInfo.VMS,
				Swap: memInfo.Swap,
			}
		}

		// Liczba wątków
		numThreads, err := proc.NumThreads()
		if err == nil {
			processInfo.NumThreads = numThreads
		}

		// Linia poleceń
		cmdline, err := proc.Cmdline()
		if err == nil {
			processInfo.Cmdline = strings.Split(cmdline, " ")
		}

		// Katalog roboczy
		cwd, err := proc.Cwd()
		if err == nil {
			processInfo.CWD = cwd
		}

		// Sprawdź, czy proces jest związany z LLM
		processInfo.IsLLMRelated = isLLMProcess(proc, name, cmdline)

		// Zbierz dodatkowe informacje dla procesów związanych z LLM
		if processInfo.IsLLMRelated {
			// Pobierz rodzica (PPID)
			ppid, err := proc.Ppid()
			if err == nil {
				processInfo.PPID = int32(ppid)
			}

			// Otwarte pliki
			openFiles, err := proc.OpenFiles()
			if err == nil && len(openFiles) > 0 {
				files := make([]models.OpenFile, 0, len(openFiles))
				for _, file := range openFiles {
					fileInfo := models.OpenFile{
						Path: file.Path,
						FD:   uint64(file.Fd),
					}
					files = append(files, fileInfo)
				}
				processInfo.OpenFiles = files
			}

			// Połączenia sieciowe
			connections, err := proc.Connections()
			if err == nil && len(connections) > 0 {
				conns := make([]models.Connection, 0, len(connections))
				for _, conn := range connections {
					connInfo := models.Connection{
						FD:     conn.Fd,
						Family: fmt.Sprintf("%v", conn.Family),
						Type:   fmt.Sprintf("%v", conn.Type),
						Status: conn.Status,
					}

					// Adres lokalny
					connInfo.LocalAddress = &models.SocketAddress{
						IP:   conn.Laddr.IP,
						Port: conn.Laddr.Port,
					}

					// Adres zdalny, jeśli istnieje
					if conn.Raddr.IP != "" {
						connInfo.RemoteAddress = &models.SocketAddress{
							IP:   conn.Raddr.IP,
							Port: conn.Raddr.Port,
						}
					}

					conns = append(conns, connInfo)
				}
				processInfo.Connections = conns
			}

			// Liczniki I/O
			ioCounters, err := proc.IOCounters()
			if err == nil {
				processInfo.IOCounters = &models.IOCounters{
					ReadCount:  ioCounters.ReadCount,
					WriteCount: ioCounters.WriteCount,
					ReadBytes:  ioCounters.ReadBytes,
					WriteBytes: ioCounters.WriteBytes,
				}
			}

			// Zmienne środowiskowe (tylko dla procesów LLM)
			environ, err := proc.Environ()
			if err == nil {
				// Filtruj poufne dane w zmiennych środowiskowych
				filtered := filterEnvironment(environ)
				processInfo.Environment = filtered
			}
		}

		// Dodaj proces do listy
		processes = append(processes, processInfo)
	}

	return processes, nil
}

// isLLMProcess sprawdza, czy proces jest potencjalnie związany z LLM
func isLLMProcess(proc *process.Process, name string, cmdline string) bool {
	// Sprawdź nazwę procesu
	nameLower := strings.ToLower(name)
	for _, keyword := range llmKeywords {
		if strings.Contains(nameLower, keyword) {
			return true
		}
	}

	// Sprawdź linię poleceń
	cmdlineLower := strings.ToLower(cmdline)
	for _, keyword := range llmKeywords {
		if strings.Contains(cmdlineLower, keyword) {
			return true
		}
	}

	// Sprawdź zmienne środowiskowe
	environ, err := proc.Environ()
	if err == nil {
		environStr := strings.ToLower(strings.Join(environ, " "))
		for _, keyword := range llmKeywords {
			if strings.Contains(environStr, keyword) {
				return true
			}
		}
	}

	return false
}

// processExists sprawdza, czy proces jeszcze istnieje
func processExists(proc *process.Process) bool {
	_, err := proc.Status()
	return err == nil
}

// filterEnvironment filtruje poufne dane w zmiennych środowiskowych
func filterEnvironment(environ []string) []string {
	filtered := make([]string, 0, len(environ))
	sensitiveKeys := []string{
		"PASSWORD", "SECRET", "KEY", "TOKEN", "CREDENTIAL", "AUTH",
	}

	for _, env := range environ {
		// Podziel zmienną na klucz i wartość
		parts := strings.SplitN(env, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := parts[0]
		isSensitive := false

		// Sprawdź, czy klucz zawiera słowo wskazujące na poufne dane
		for _, sensitiveKey := range sensitiveKeys {
			if strings.Contains(strings.ToUpper(key), sensitiveKey) {
				isSensitive = true
				break
			}
		}

		// Dodaj zmienną do filtrowanej listy
		if isSensitive {
			filtered = append(filtered, key+"=***FILTERED***")
		} else {
			filtered = append(filtered, env)
		}
	}

	return filtered
}

// CollectLLMProcesses zbiera informacje tylko o procesach związanych z LLM
func CollectLLMProcesses() ([]models.Process, error) {
	processes, err := CollectProcessesInfo()
	if err != nil {
		return nil, err
	}

	llmProcesses := make([]models.Process, 0)
	for _, p := range processes {
		if p.IsLLMRelated {
			llmProcesses = append(llmProcesses, p)
		}
	}

	return llmProcesses, nil
}

// getProcessTree zwraca drzewo procesów dla danego PID
func getProcessTree(pid int32) ([]models.Process, error) {
	processes, err := CollectProcessesInfo()
	if err != nil {
		return nil, err
	}

	// Znajdź proces główny
	var rootProcess *models.Process
	for i, p := range processes {
		if p.PID == pid {
			rootProcess = &processes[i]
			break
		}
	}

	if rootProcess == nil {
		return nil, fmt.Errorf("proces o PID %d nie został znaleziony", pid)
	}

	// Utwórz mapę PPID -> [PID]
	pidMap := make(map[int32][]int32)
	for _, p := range processes {
		if p.PPID > 0 {
			pidMap[p.PPID] = append(pidMap[p.PPID], p.PID)
		}
	}

	// Zbierz wszystkie procesy potomne
	tree := []models.Process{*rootProcess}
	queue := []int32{rootProcess.PID}

	for len(queue) > 0 {
		current := queue[0]
		queue = queue[1:]

		for _, childPID := range pidMap[current] {
			for i, p := range processes {
				if p.PID == childPID {
					tree = append(tree, processes[i])
					queue = append(queue, childPID)
					break
				}
			}
		}
	}

	return tree, nil
}