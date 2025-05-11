package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/docker"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	"github.com/shirou/gopsutil/v3/process"
)

// Konfiguracja agenta
type Config struct {
	Interval    int    `json:"interval"`    // Interwał odczytu w sekundach
	BridgeURL   string `json:"bridge_url"`  // URL do VM Bridge
	LogFile     string `json:"log_file"`    // Plik dziennika
	StateDir    string `json:"state_dir"`   // Katalog na dane stanu
	IncludeProc bool   `json:"include_proc"` // Czy zbierać dane o procesach
	IncludeNet  bool   `json:"include_net"`  // Czy zbierać dane o sieci
	Verbose     bool   `json:"verbose"`     // Tryb szczegółowego logowania
}

// SystemState przechowuje kompletny stan systemu
type SystemState struct {
	Timestamp string                 `json:"timestamp"`
	Hardware  map[string]interface{} `json:"hardware"`
	Services  []interface{}          `json:"services"`
	Processes []interface{}          `json:"processes"`
}

func main() {
	// Parsowanie argumentów linii poleceń
	interval := flag.Int("interval", 10, "Interwał odczytu w sekundach")
	bridgeURL := flag.String("bridge", "http://localhost:5678/api/v1/update_state", "URL do VM Bridge")
	logFile := flag.String("log", "/var/log/safetytwin-agent.log", "Plik dziennika")
	stateDir := flag.String("state-dir", "/var/lib/safetytwin/states", "Katalog na dane stanu")
	includeProc := flag.Bool("proc", true, "Czy zbierać dane o procesach")
	includeNet := flag.Bool("net", true, "Czy zbierać dane o sieci")
	verbose := flag.Bool("verbose", false, "Tryb szczegółowego logowania")
	flag.Parse()

	// Inicjalizacja konfiguracji
	config := Config{
		Interval:    *interval,
		BridgeURL:   *bridgeURL,
		LogFile:     *logFile,
		StateDir:    *stateDir,
		IncludeProc: *includeProc,
		IncludeNet:  *includeNet,
		Verbose:     *verbose,
	}

	// Konfiguracja logowania
	if err := configureLogging(config.LogFile); err != nil {
		fmt.Printf("Błąd podczas konfiguracji logowania: %v\n", err)
		os.Exit(1)
	}

	// Utwórz katalog stanów, jeśli nie istnieje
	if err := os.MkdirAll(config.StateDir, 0755); err != nil {
		log.Fatalf("Nie można utworzyć katalogu stanów: %v", err)
	}

	log.Printf("Agent cyfrowego bliźniaka uruchomiony. Interwał: %d sekund", config.Interval)

	// Główna pętla zbierania danych
	ticker := time.NewTicker(time.Duration(config.Interval) * time.Second)
	defer ticker.Stop()

	// Natychmiastowe pierwsze zbieranie danych
	collectAndSendState(config)

	// Pętla zbierania danych
	for {
		select {
		case <-ticker.C:
			collectAndSendState(config)
		}
	}
}

// Konfiguracja logowania
func configureLogging(logFile string) error {
	file, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}

	log.SetOutput(file)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)
	return nil
}

// Główna funkcja zbierająca i wysyłająca stan systemu
func collectAndSendState(config Config) {
	startTime := time.Now()
	log.Println("Rozpoczęcie zbierania danych o systemie...")

	// Zbierz dane o systemie
	state := SystemState{
		Timestamp: time.Now().Format(time.RFC3339),
		Hardware:  collectHardwareInfo(),
		Services:  collectServicesInfo(),
	}

	// Opcjonalnie zbierz dane o procesach
	if config.IncludeProc {
		state.Processes = collectProcessesInfo()
	}

	// Zapisz stan do pliku
	stateFile := filepath.Join(config.StateDir, fmt.Sprintf("state_%s.json", 
		time.Now().Format("20060102_150405")))
	
	if jsonData, err := json.MarshalIndent(state, "", "  "); err == nil {
		if err := os.WriteFile(stateFile, jsonData, 0644); err != nil {
			log.Printf("Błąd podczas zapisywania stanu do pliku: %v", err)
		}
	} else {
		log.Printf("Błąd podczas serializacji stanu: %v", err)
	}

	// Wyślij dane do VM Bridge
	if err := sendStateToBridge(config.BridgeURL, state); err != nil {
		log.Printf("Błąd podczas wysyłania stanu do VM Bridge: %v", err)
	}

	elapsedTime := time.Since(startTime)
	log.Printf("Zbieranie danych zakończone. Czas: %v", elapsedTime)
}

// Zbieranie informacji o sprzęcie
func collectHardwareInfo() map[string]interface{} {
	hardwareInfo := make(map[string]interface{})

	// Informacje o hoście
	if hostInfo, err := host.Info(); err == nil {
		hardwareInfo["hostname"] = hostInfo.Hostname
		hardwareInfo["platform"] = hostInfo.Platform
		hardwareInfo["platform_version"] = hostInfo.PlatformVersion
		hardwareInfo["os"] = hostInfo.OS
		hardwareInfo["kernel_version"] = hostInfo.KernelVersion
		hardwareInfo["uptime"] = hostInfo.Uptime
	} else {
		log.Printf("Błąd podczas zbierania informacji o hoście: %v", err)
	}

	// Informacje o CPU
	cpuInfo := make(map[string]interface{})
	if cpuStats, err := cpu.Info(); err == nil {
		cpuInfo["model"] = cpuStats[0].ModelName
		cpuInfo["cores_physical"] = cpuStats[0].Cores
	}
	
	// Liczba logicznych rdzeni
	cpuInfo["count_logical"] = runtime.NumCPU()
	
	// Wykorzystanie CPU
	if cpuPercent, err := cpu.Percent(time.Second, false); err == nil {
		cpuInfo["usage_percent"] = cpuPercent[0]
	}
	
	// Wykorzystanie CPU per rdzeń
	if perCPUPercent, err := cpu.Percent(time.Second, true); err == nil {
		cpuPerCore := make([]map[string]float64, len(perCPUPercent))
		for i, percent := range perCPUPercent {
			cpuPerCore[i] = map[string]float64{"usage_percent": percent}
		}
		cpuInfo["per_cpu"] = cpuPerCore
	}
	
	hardwareInfo["cpu"] = cpuInfo

	// Informacje o pamięci
	if memInfo, err := mem.VirtualMemory(); err == nil {
		hardwareInfo["memory"] = map[string]interface{}{
			"total_gb":      float64(memInfo.Total) / (1024 * 1024 * 1024),
			"available_gb":  float64(memInfo.Available) / (1024 * 1024 * 1024),
			"used_gb":       float64(memInfo.Used) / (1024 * 1024 * 1024),
			"free_gb":       float64(memInfo.Free) / (1024 * 1024 * 1024),
			"percent":       memInfo.UsedPercent,
			"swap_total_gb": float64(memInfo.SwapTotal) / (1024 * 1024 * 1024),
			"swap_used_gb":  float64(memInfo.SwapTotal-memInfo.SwapFree) / (1024 * 1024 * 1024),
		}
	}

	// Informacje o dyskach
	disks := []map[string]interface{}{}
	if partitions, err := disk.Partitions(false); err == nil {
		for _, partition := range partitions {
			if usage, err := disk.Usage(partition.Mountpoint); err == nil {
				diskInfo := map[string]interface{}{
					"device":     partition.Device,
					"mountpoint": partition.Mountpoint,
					"fstype":     partition.Fstype,
					"total_gb":   float64(usage.Total) / (1024 * 1024 * 1024),
					"used_gb":    float64(usage.Used) / (1024 * 1024 * 1024),
					"free_gb":    float64(usage.Free) / (1024 * 1024 * 1024),
					"percent":    usage.UsedPercent,
				}
				disks = append(disks, diskInfo)
			}
		}
		hardwareInfo["disks"] = disks
	}

	// Informacje o interfejsach sieciowych
	if interfaces, err := net.Interfaces(); err == nil {
		networkInfo := make(map[string]interface{})
		
		for _, iface := range interfaces {
			if len(iface.Addrs) > 0 {
				ifaceInfo := map[string]interface{}{
					"name":    iface.Name,
					"mac":     iface.HardwareAddr,
					"addresses": iface.Addrs,
					"flags":   iface.Flags,
				}
				networkInfo[iface.Name] = ifaceInfo
			}
		}
		
		// Statystyki interfejsów
		if ioCounters, err := net.IOCounters(true); err == nil {
			for _, counter := range ioCounters {
				if ifaceInfo, ok := networkInfo[counter.Name].(map[string]interface{}); ok {
					ifaceInfo["bytes_sent"] = counter.BytesSent
					ifaceInfo["bytes_recv"] = counter.BytesRecv
					ifaceInfo["packets_sent"] = counter.PacketsSent
					ifaceInfo["packets_recv"] = counter.PacketsRecv
					ifaceInfo["errin"] = counter.Errin
					ifaceInfo["errout"] = counter.Errout
					ifaceInfo["dropin"] = counter.Dropin
					ifaceInfo["dropout"] = counter.Dropout
				}
			}
		}
		
		hardwareInfo["network"] = networkInfo
	}

	return hardwareInfo
}

// Lista słów kluczowych do identyfikacji procesów LLM
var llmKeywords = []string{
	"python", "python3", "llama", "gpt", "bert", "transformer",
	"pytorch", "tensorflow", "onnxruntime", "huggingface",
	"langchain", "llm", "openai", "mistral", "vicuna", "falcon",
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

// Zbieranie informacji o procesach
func collectProcessesInfo() []interface{} {
	processes := []interface{}{}
	
	// Pobierz wszystkie procesy
	procs, err := process.Processes()
	if err != nil {
		log.Printf("Błąd podczas pobierania listy procesów: %v", err)
		return processes
	}
	
	// Przetwórz każdy proces
	for _, proc := range procs {
		procInfo := make(map[string]interface{})
		
		// Podstawowe informacje
		procInfo["pid"] = proc.Pid
		
		// Nazwa procesu
		if name, err := proc.Name(); err == nil {
			procInfo["name"] = name
			
			// Linia poleceń
			var cmdline string
			if cmdlineSlice, err := proc.Cmdline(); err == nil {
				cmdline = cmdlineSlice
				procInfo["cmdline"] = strings.Split(cmdline, " ")
			}
			
			// Sprawdź, czy to jest proces LLM
			isLLM := isLLMProcess(proc, name, cmdline)
			procInfo["is_llm_related"] = isLLM
			
			// Status
			if status, err := proc.Status(); err == nil {
				procInfo["status"] = status
			}
			
			// Użytkownik
			if username, err := proc.Username(); err == nil {
				procInfo["username"] = username
			}
			
			// Czas utworzenia
			if createTime, err := proc.CreateTime(); err == nil {
				procInfo["create_time"] = time.Unix(createTime/1000, 0).Format(time.RFC3339)
			}
			
			// Wykorzystanie CPU i pamięci
			if cpuPercent, err := proc.CPUPercent(); err == nil {
				procInfo["cpu_percent"] = cpuPercent
			}
			
			if memPercent, err := proc.MemoryPercent(); err == nil {
				procInfo["memory_percent"] = memPercent
			}
			
			// Informacje o pamięci
			if memInfo, err := proc.MemoryInfo(); err == nil {
				procInfo["memory_info"] = map[string]uint64{
					"rss":  memInfo.RSS,
					"vms":  memInfo.VMS,
					"swap": memInfo.Swap,
				}
			}
			
			// Liczba wątków
			if numThreads, err := proc.NumThreads(); err == nil {
				procInfo["num_threads"] = numThreads
			}
			
			// Katalog roboczy
			if cwd, err := proc.Cwd(); err == nil {
				procInfo["cwd"] = cwd
			}
			
			// Jeśli to proces związany z LLM, zbierz więcej informacji
			if isLLM {
				// Otwarte pliki
				if openFiles, err := proc.OpenFiles(); err == nil {
					files := []map[string]interface{}{}
					for _, file := range openFiles {
						files = append(files, map[string]interface{}{
							"path": file.Path,
							"fd":   file.Fd,
						})
					}
					procInfo["open_files"] = files
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
					procInfo["connections"] = conns
				}
				
				// Liczniki I/O
				if ioCounters, err := proc.IOCounters(); err == nil {
					procInfo["io_counters"] = map[string]interface{}{
						"read_count":  ioCounters.ReadCount,
						"write_count": ioCounters.WriteCount,
						"read_bytes":  ioCounters.ReadBytes,
						"write_bytes": ioCounters.WriteBytes,
					}
				}
			}
			
			processes = append(processes, procInfo)
		}
	}
	
	return processes
}

// Zbieranie informacji o usługach systemowych i kontenerach Docker
func collectServicesInfo() []interface{} {
	services := []interface{}{}
	
	// Zbierz informacje o usługach systemd
	systemdServices := collectSystemdServices()
	services = append(services, systemdServices...)
	
	// Zbierz informacje o kontenerach Docker
	dockerContainers := collectDockerContainers()
	services = append(services, dockerContainers...)
	
	return services
}

// Zbieranie informacji o usługach systemd
func collectSystemdServices() []interface{} {
	services := []interface{}{}
	
	// Sprawdź, czy systemd jest dostępny
	if _, err := os.Stat("/run/systemd/system"); os.IsNotExist(err) {
		log.Println("Systemd nie jest dostępny na tym systemie")
		return services
	}
	
	// Wykonaj komendę systemctl
	cmd := exec.Command("systemctl", "list-units", "--type=service", "--all", "--no-pager")
	output, err := cmd.Output()
	if err != nil {
		log.Printf("Błąd podczas wykonywania komendy systemctl: %v", err)
		return services
	}
	
	// Parsuj wynik
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.TrimSpace(line) == "" || strings.Contains(line, "UNIT") || strings.Contains(line, "LOAD") {
			continue
		}
		
		fields := strings.Fields(line)
		if len(fields) >= 3 && strings.HasSuffix(fields[0], ".service") {
			serviceName := fields[0]
			
			// Pobierz szczegółowe informacje o usłudze
			serviceInfo := map[string]interface{}{
				"name":      serviceName,
				"type":      "systemd",
				"timestamp": time.Now().Format(time.RFC3339),
			}
			
			// Status usługi
			cmd = exec.Command("systemctl", "status", serviceName, "--no-pager")
			statusOutput, _ := cmd.Output()
			statusStr := string(statusOutput)
			
			// Wyciągnij status (active/inactive)
			if strings.Contains(statusStr, "Active: active") {
				serviceInfo["status"] = "active"
			} else if strings.Contains(statusStr, "Active: inactive") {
				serviceInfo["status"] = "inactive"
			} else {
				serviceInfo["status"] = "unknown"
			}
			
			// Wyciągnij PID
			pidMatch := strings.Index(statusStr, "Main PID: ")
			if pidMatch >= 0 {
				pidStr := statusStr[pidMatch+10:]
				pidEnd := strings.Index(pidStr, " ")
				if pidEnd > 0 {
					pidStr = pidStr[:pidEnd]
				}
				if pid, err := fmt.Sscanf(pidStr, "%d", new(int)); err == nil && pid > 0 {
					serviceInfo["pid"] = pid
				}
			}
			
			services = append(services, serviceInfo)
		}
	}
	
	return services
}

// Zbieranie informacji o kontenerach Docker
func collectDockerContainers() []interface{} {
	services := []interface{}{}
	
	// Sprawdź, czy Docker jest dostępny
	if _, err := exec.LookPath("docker"); err != nil {
		log.Println("Docker nie jest dostępny na tym systemie")
		return services
	}
	
	// Wykonaj komendę Docker
	cmd := exec.Command("docker", "ps", "-a", "--format", "{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}\\t{{.Command}}")
	output, err := cmd.Output()
	if err != nil {
		log.Printf("Błąd podczas wykonywania komendy docker: %v", err)
		return services
	}
	
	// Parsuj wynik
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		
		fields := strings.Split(line, "\t")
		if len(fields) >= 4 {
			containerId := fields[0]
			containerName := fields[1]
			containerImage := fields[2]
			containerStatus := fields[3]
			
			// Pobierz szczegółowe informacje o kontenerze
			serviceInfo := map[string]interface{}{
				"name":      containerName,
				"type":      "docker",
				"id":        containerId,
				"image":     containerImage,
				"status":    strings.HasPrefix(containerStatus, "Up") ? "running" : "stopped",
				"timestamp": time.Now().Format(time.RFC3339),
			}
			
			// Porty
			if len(fields) >= 5 && fields[4] != "" {
				ports := []map[string]string{}
				portMappings := strings.Split(fields[4], ", ")
				for _, portMapping := range portMappings {
					parts := strings.Split(portMapping, "->")
					if len(parts) == 2 {
						hostPart := strings.Split(parts[0], ":")
						containerPort := parts[1]
						
						portInfo := map[string]string{}
						if len(hostPart) == 2 {
							portInfo["host_ip"] = hostPart[0]
							portInfo["host_port"] = hostPart[1]
						} else {
							portInfo["host_port"] = hostPart[0]
						}
						portInfo["container_port"] = containerPort
						
						ports = append(ports, portInfo)
					}
				}
				serviceInfo["ports"] = ports
			}
			
			// Wykonaj komendę inspect, aby uzyskać więcej informacji
			cmd = exec.Command("docker", "inspect", containerId)
			inspectOutput, err := cmd.Output()
			if err == nil {
				var inspectData []map[string]interface{}
				if err := json.Unmarshal(inspectOutput, &inspectData); err == nil && len(inspectData) > 0 {
					containerData := inspectData[0]
					
					// Wolumeny
					if mounts, ok := containerData["Mounts"].([]interface{}); ok {
						volumes := []map[string]interface{}{}
						for _, mount := range mounts {
							if mountData, ok := mount.(map[string]interface{}); ok {
								volumeInfo := map[string]interface{}{
									"type":        mountData["Type"],
									"source":      mountData["Source"],
									"destination": mountData["Destination"],
									"read_only":   mountData["RO"],
								}
								volumes = append(volumes, volumeInfo)
							}
						}
						serviceInfo["volumes"] = volumes
					}
					
					// Zmienne środowiskowe
					if config, ok := containerData["Config"].(map[string]interface{}); ok {
						if env, ok := config["Env"].([]interface{}); ok {
							serviceInfo["environment"] = env
						}
					}
					
					// Sprawdź, czy to kontener z LLM
					isLLM := false
					
					// Sprawdź nazwę obrazu
					imageLower := strings.ToLower(containerImage)
					for _, keyword := range llmKeywords {
						if strings.Contains(imageLower, keyword) {
							isLLM = true
							break
						}
					}
					
					// Sprawdź zmienne środowiskowe
					if env, ok := serviceInfo["environment"].([]interface{}); ok {
						envStr := strings.ToLower(fmt.Sprintf("%v", env))
						for _, keyword := range llmKeywords {
							if strings.Contains(envStr, keyword) {
								isLLM = true
								break
							}
						}
					}
					
					serviceInfo["is_llm_related"] = isLLM
				}
			}
			
			services = append(services, serviceInfo)
		}
	}
	
	return services
}

// Wysyłanie stanu systemu do VM Bridge
func sendStateToBridge(url string, state SystemState) error {
	// Serializuj dane do JSON
	jsonData, err := json.Marshal(state)
	if err != nil {
		return fmt.Errorf("błąd serializacji danych: %v", err)
	}
	
	// Wyślij żądanie POST
	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("błąd wysyłania żądania: %v", err)
	}
	defer resp.Body.Close()
	
	// Sprawdź kod odpowiedzi
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("nieoczekiwany kod odpowiedzi: %d", resp.StatusCode)
	}
	
	return nil
}
