package collectors

import (
	"digital-twin/agent/models"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/process"
)

// CollectProcessesInfo zbiera informacje o procesach
func CollectProcessesInfo() ([]models.Process, error) {
	processes := []models.Process{}
	
	// Pobierz wszystkie procesy
	procs, err := process.Processes()
	if err != nil {
		return nil, fmt.Errorf("błąd podczas pobierania listy procesów: %v", err)
	}
	
	// Przetwórz każdy proces
	for _, proc := range procs {
		procInfo := models.Process{
			PID: proc.Pid,
		}
		
		// Nazwa procesu
		if name, err := proc.Name(); err == nil {
			procInfo.Name = name
			
			// Linia poleceń
			if cmdlineStr, err := proc.Cmdline(); err == nil && cmdlineStr != "" {
				procInfo.Cmdline = strings.Split(cmdlineStr, " ")
				
				// Sprawdź, czy to jest proces LLM
				procInfo.IsLLMRelated = isLLMProcess(proc, name, cmdlineStr)
				
				// Status
				if status, err := proc.Status(); err == nil {
					procInfo.Status = status
				}
				
				// Użytkownik
				if username, err := proc.Username(); err == nil {
					procInfo.Username = username
				}
				
				// Czas utworzenia
				if createTime, err := proc.CreateTime(); err == nil {
					procInfo.CreateTime = time.Unix(createTime/1000, 0).Format(time.RFC3339)
				}
				
				// Wykorzystanie CPU i pamięci
				if cpuPercent, err := proc.CPUPercent(); err == nil {
					procInfo.CPUPercent = cpuPercent
				}
				
				if memPercent, err := proc.MemoryPercent(); err == nil {
					procInfo.MemoryPercent = memPercent
				}
				
				// Informacje o pamięci
				if memInfo, err := proc.MemoryInfo(); err == nil {
					procInfo.MemoryInfo = map[string]uint64{
						"rss":  memInfo.RSS,
						"vms":  memInfo.VMS,
						"swap": memInfo.Swap,
					}
				}
				
				// Liczba wątków
				if numThreads, err := proc.NumThreads(); err == nil {
					procInfo.NumThreads = numThreads
				}
				
				// Katalog roboczy
				if cwd, err := proc.Cwd(); err == nil {
					procInfo.Cwd = cwd
				}
				
				// Jeśli to proces związany z LLM, zbierz więcej informacji
				if procInfo.IsLLMRelated {
					collectExtendedProcessInfo(&procInfo, proc)
				}
				
				processes = append(processes, procInfo)
			}
		}
	}
	
	return processes, nil
}

// Sprawdza, czy proces jest potencjalnie związany z LLM
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

// Zbiera rozszerzone informacje o procesie (dla procesów LLM)
func collectExtendedProcessInfo(procInfo *models.Process, proc *process.Process) {
	// Otwarte pliki
	if openFiles, err := proc.OpenFiles(); err == nil {
		files := []map[string]interface{}{}
		for _, file := range openFiles {
			files = append(files, map[string]interface{}{
				"path": file.Path,
				"fd":   file.Fd,
			})
		}
		procInfo.OpenFiles = files
	}
	
	// Połączenia sieciowe
	if connections, err := proc.Connections(); err == nil {
		conns := []map[string]interface{}{}
		for _, conn := range connections {
			connInfo := map[string]interface{}{
				"fd":     conn.Fd,
				"family": conn.Family.String(),
				"type":   conn.Type.String(),
				"status": conn.Status,
			}
			
			// Adresy lokalne
			connInfo["local_address"] = map[string]interface{}{
				"ip":   conn.Laddr.IP,
				"port": conn.Laddr.Port,
			}
			
			// Adresy zdalne
			if conn.Raddr.IP != "" {
				connInfo["remote_address"] = map[string]interface{}{
					"ip":   conn.Raddr.IP,
					"port": conn.Raddr.Port,
				}
			}
			
			conns = append(conns, connInfo)
		}
		procInfo.Connections = conns
	}
	
	// Liczniki I/O
	if ioCounters, err := proc.IOCounters(); err == nil {
		procInfo.IOCounters = map[string]interface{}{
			"read_count":  ioCounters.ReadCount,
			"write_count": ioCounters.WriteCount,
			"read_bytes":  ioCounters.ReadBytes,
			"write_bytes": ioCounters.WriteBytes,
		}
	}
}
