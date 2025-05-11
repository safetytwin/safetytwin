package collectors

import (
	"digital-twin/agent/models"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
)

// CollectHardwareInfo zbiera informacje o sprzęcie komputerowym
func CollectHardwareInfo() (*models.Hardware, error) {
	hardware := &models.Hardware{}

	// Informacje o hoście
	if hostInfo, err := host.Info(); err == nil {
		hardware.Hostname = hostInfo.Hostname
		hardware.Platform = hostInfo.Platform
		hardware.PlatformVersion = hostInfo.PlatformVersion
		hardware.KernelVersion = hostInfo.KernelVersion
		hardware.OS = hostInfo.OS
		hardware.Uptime = hostInfo.Uptime
	} else {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o hoście: %v", err)
	}

	// Informacje o CPU
	hardware.CPU = &models.CPU{}
	if cpuInfo, err := cpu.Info(); err == nil && len(cpuInfo) > 0 {
		hardware.CPU.Model = cpuInfo[0].ModelName
		hardware.CPU.PhysicalCores = int(cpuInfo[0].Cores)
		hardware.CPU.LogicalCores = runtime.NumCPU()
	}

	// Wykorzystanie CPU
	if cpuPercent, err := cpu.Percent(time.Second, false); err == nil && len(cpuPercent) > 0 {
		hardware.CPU.UsagePercent = cpuPercent[0]
	}

	// Wykorzystanie CPU per rdzeń
	if perCPUPercent, err := cpu.Percent(time.Second, true); err == nil {
		hardware.CPU.PerCPU = make([]models.CPUCore, len(perCPUPercent))
		for i, percent := range perCPUPercent {
			hardware.CPU.PerCPU[i] = models.CPUCore{
				UsagePercent: percent,
			}
		}
	}

	// Informacje o pamięci
	if memInfo, err := mem.VirtualMemory(); err == nil {
		hardware.Memory = &models.Memory{
			TotalGB:     float64(memInfo.Total) / (1024 * 1024 * 1024),
			AvailableGB: float64(memInfo.Available) / (1024 * 1024 * 1024),
			UsedGB:      float64(memInfo.Used) / (1024 * 1024 * 1024),
			FreeGB:      float64(memInfo.Free) / (1024 * 1024 * 1024),
			Percent:     memInfo.UsedPercent,
		}

		// Informacje o swapie
		if swapInfo, err := mem.SwapMemory(); err == nil {
			hardware.Memory.SwapTotalGB = float64(swapInfo.Total) / (1024 * 1024 * 1024)
			hardware.Memory.SwapUsedGB = float64(swapInfo.Used) / (1024 * 1024 * 1024)
			hardware.Memory.SwapPercent = swapInfo.UsedPercent
		}
	}

	// Informacje o dyskach
	if partitions, err := disk.Partitions(false); err == nil {
		hardware.Disks = make([]models.Disk, 0, len(partitions))
		for _, partition := range partitions {
			if usage, err := disk.Usage(partition.Mountpoint); err == nil {
				disk := models.Disk{
					Device:     partition.Device,
					Mountpoint: partition.Mountpoint,
					Fstype:     partition.Fstype,
					TotalGB:    float64(usage.Total) / (1024 * 1024 * 1024),
					UsedGB:     float64(usage.Used) / (1024 * 1024 * 1024),
					FreeGB:     float64(usage.Free) / (1024 * 1024 * 1024),
					Percent:    usage.UsedPercent,
				}
				hardware.Disks = append(hardware.Disks, disk)
			}
		}
	}

	// Informacje o sieci
	if interfaces, err := net.Interfaces(); err == nil {
		hardware.Network = make(map[string]models.NetworkInterface)
		
		for _, iface := range interfaces {
			if len(iface.Addrs) > 0 {
				netIf := models.NetworkInterface{
					Name:      iface.Name,
					MAC:       iface.HardwareAddr,
					Addresses: make([]string, 0, len(iface.Addrs)),
					Flags:     iface.Flags,
				}
				
				for _, addr := range iface.Addrs {
					netIf.Addresses = append(netIf.Addresses, addr.Addr)
				}
				
				hardware.Network[iface.Name] = netIf
			}
		}
		
		// Statystyki sieci
		if ioCounters, err := net.IOCounters(true); err == nil {
			for _, counter := range ioCounters {
				if netIf, ok := hardware.Network[counter.Name]; ok {
					netIf.BytesSent = counter.BytesSent
					netIf.BytesRecv = counter.BytesRecv
					netIf.PacketsSent = counter.PacketsSent
					netIf.PacketsRecv = counter.PacketsRecv
					netIf.Errin = counter.Errin
					netIf.Errout = counter.Errout
					netIf.Dropin = counter.Dropin
					netIf.Dropout = counter.Dropout
					
					hardware.Network[counter.Name] = netIf
				}
			}
		}
	}

	// Informacje o GPU (tylko dla NVIDIA)
	hardware.GPU = collectGPUInfo()

	return hardware, nil
}

// collectGPUInfo zbiera informacje o kartach graficznych NVIDIA
func collectGPUInfo() map[string][]models.GPUDevice {
	gpus := make(map[string][]models.GPUDevice)
	
	// Sprawdź, czy nvidia-smi jest dostępne
	if _, err := exec.LookPath("nvidia-smi"); err != nil {
		return gpus
	}
	
	// Uruchom nvidia-smi
	cmd := exec.Command("nvidia-smi", "--query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits")
	output, err := cmd.Output()
	if err != nil {
		return gpus
	}
	
	// Parsuj wynik
	nvidiaGPUs := make([]models.GPUDevice, 0)
	lines := strings.Split(string(output), "\n")
	
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		
		fields := strings.Split(line, ", ")
		if len(fields) < 6 {
			continue
		}
		
		// Parsuj pola
		var index int
		var temperature, utilization, memoryUsed, memoryTotal float64
		
		fmt.Sscanf(fields[0], "%d", &index)
		fmt.Sscanf(fields[2], "%f", &temperature)
		fmt.Sscanf(fields[3], "%f", &utilization)
		fmt.Sscanf(fields[4], "%f", &memoryUsed)
		fmt.Sscanf(fields[5], "%f", &memoryTotal)
		
		gpu := models.GPUDevice{
			Index:           index,
			Name:            fields[1],
			Temperature:     temperature,
			UtilizationGPU:  utilization,
			MemoryUsedMB:    memoryUsed,
			MemoryTotalMB:   memoryTotal,
		}
		
		nvidiaGPUs = append(nvidiaGPUs, gpu)
	}
	
	if len(nvidiaGPUs) > 0 {
		gpus["nvidia"] = nvidiaGPUs
	}
	
	return gpus
}

// GetKernelParameter odczytuje parametr jądra z /proc/sys
func GetKernelParameter(param string) (string, error) {
	path := "/proc/sys/" + param
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"

	"github.com/NVIDIA/go-nvml/pkg/nvml"

	"gitlab.com/safetytwin/safetytwin/agent/models"
)

// HardwareCollector zbiera informacje o sprzęcie
type HardwareCollector struct {}

// NewHardwareCollector tworzy nowy kolektor informacji o sprzęcie
func NewHardwareCollector() *HardwareCollector {
	return &HardwareCollector{}
}

// Collect zbiera informacje o sprzęcie i zwraca wypełniony obiekt Hardware
func (c *HardwareCollector) Collect() (*models.Hardware, error) {
	hardware := &models.Hardware{}

	// Zbierz podstawowe informacje o hoście
	if err := c.collectHostInfo(hardware); err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o hoście: %v", err)
	}

	// Zbierz informacje o CPU
	if err := c.collectCPUInfo(hardware); err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o CPU: %v", err)
	}

	// Zbierz informacje o pamięci
	if err := c.collectMemoryInfo(hardware); err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o pamięci: %v", err)
	}

	// Zbierz informacje o dyskach
	if err := c.collectDiskInfo(hardware); err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o dyskach: %v", err)
	}

	// Zbierz informacje o sieci
	if err := c.collectNetworkInfo(hardware); err != nil {
		return nil, fmt.Errorf("błąd podczas zbierania informacji o sieci: %v", err)
	}

	// Zbierz informacje o GPU
	if err := c.collectGPUInfo(hardware); err != nil {
		// Obsługa błędu jako ostrzeżenie, nie krytyczny błąd
		fmt.Printf("Ostrzeżenie: nie można zebrać informacji o GPU: %v\n", err)
	}

	return hardware, nil
}

// collectHostInfo zbiera podstawowe informacje o hoście
func (c *HardwareCollector) collectHostInfo(hardware *models.Hardware) error {
	// Pobierz nazwę hosta
	hostname, err := os.Hostname()
	if err != nil {
		return fmt.Errorf("nie można pobrać nazwy hosta: %v", err)
	}
	hardware.Hostname = hostname

	// Pobierz informacje o platformie
	info, err := host.Info()
	if err != nil {
		return fmt.Errorf("nie można pobrać informacji o hoście: %v", err)
	}

	hardware.Platform = info.Platform
	hardware.PlatformVersion = info.PlatformVersion
	hardware.KernelVersion = info.KernelVersion
	hardware.OS = info.OS
	hardware.Uptime = info.Uptime

	return nil
}

// collectCPUInfo zbiera informacje o procesorze
func (c *HardwareCollector) collectCPUInfo(hardware *models.Hardware) error {
	// Pobierz informacje o CPU
	cpuInfo, err := cpu.Info()
	if err != nil {
		return fmt.Errorf("nie można pobrać informacji o CPU: %v", err)
	}

	if len(cpuInfo) == 0 {
		return fmt.Errorf("nie znaleziono informacji o CPU")
	}

	// Pobierz liczbę rdzeni fizycznych i logicznych
	physicalCores, err := cpu.Counts(false)
	if err != nil {
		return fmt.Errorf("nie można pobrać liczby rdzeni fizycznych: %v", err)
	}

	logicalCores, err := cpu.Counts(true)
	if err != nil {
		return fmt.Errorf("nie można pobrać liczby rdzeni logicznych: %v", err)
	}

	// Pobierz użycie CPU
	percentages, err := cpu.Percent(time.Second, false)
	if err != nil {
		return fmt.Errorf("nie można pobrać użycia CPU: %v", err)
	}

	perCPU, err := cpu.Percent(time.Second, true)
	if err != nil {
		return fmt.Errorf("nie można pobrać użycia per-CPU: %v", err)
	}

	// Utwórz i wypełnij strukturę CPU
	cpuModel := &models.CPU{
		Model:         cpuInfo[0].ModelName,
		PhysicalCores: physicalCores,
		LogicalCores:  logicalCores,
		UsagePercent:  percentages[0],
		PerCPU:        make([]models.CPUCore, len(perCPU)),
	}

	// Wypełnij informacje o każdym rdzeniu
	for i, usage := range perCPU {
		cpuModel.PerCPU[i] = models.CPUCore{
			UsagePercent: usage,
		}
	}

	hardware.CPU = cpuModel

	return nil
}

// collectMemoryInfo zbiera informacje o pamięci
func (c *HardwareCollector) collectMemoryInfo(hardware *models.Hardware) error {
	// Pobierz informacje o pamięci wirtualnej
	virtualMemory, err := mem.VirtualMemory()
	if err != nil {
		return fmt.Errorf("nie można pobrać informacji o pamięci wirtualnej: %v", err)
	}

	// Pobierz informacje o pamięci swap
	swapMemory, err := mem.SwapMemory()
	if err != nil {
		return fmt.Errorf("nie można pobrać informacji o pamięci swap: %v", err)
	}

	// Konwertuj bajty na GB
	toGB := func(bytes uint64) float64 {
		return float64(bytes) / (1024 * 1024 * 1024)
	}

	// Utwórz i wypełnij strukturę Memory
	memoryModel := &models.Memory{
		TotalGB:     toGB(virtualMemory.Total),
		AvailableGB: toGB(virtualMemory.Available),
		UsedGB:      toGB(virtualMemory.Used),
		FreeGB:      toGB(virtualMemory.Free),
		Percent:     virtualMemory.UsedPercent,
	}

	// Dodaj informacje o pamięci swap, jeśli jest dostępna
	if swapMemory.Total > 0 {
		memoryModel.SwapTotalGB = toGB(swapMemory.Total)
		memoryModel.SwapUsedGB = toGB(swapMemory.Used)
		memoryModel.SwapPercent = swapMemory.UsedPercent
	}

	hardware.Memory = memoryModel

	return nil
}

// collectDiskInfo zbiera informacje o dyskach
func (c *HardwareCollector) collectDiskInfo(hardware *models.Hardware) error {
	// Pobierz partycje
	partitions, err := disk.Partitions(false)
	if err != nil {
		return fmt.Errorf("nie można pobrać informacji o partycjach: %v", err)
	}

	// Utwórz slice na informacje o dyskach
	disks := make([]models.Disk, 0, len(partitions))

	// Konwertuj bajty na GB
	toGB := func(bytes uint64) float64 {
		return float64(bytes) / (1024 * 1024 * 1024)
	}

	// Zbierz informacje o każdej partycji
	for _, partition := range partitions {
		// Pomiń systemy plików, które nie są interesujące
		if strings.HasPrefix(partition.Mountpoint, "/sys") ||
			strings.HasPrefix(partition.Mountpoint, "/proc") ||
			strings.HasPrefix(partition.Mountpoint, "/dev") ||
			strings.HasPrefix(partition.Mountpoint, "/run") {
			continue
		}

		// Pobierz statystyki użycia
		usage, err := disk.Usage(partition.Mountpoint)
		if err != nil {
			// Loguj błąd, ale kontynuuj dla innych partycji
			fmt.Printf("Ostrzeżenie: nie można pobrać użycia dla %s: %v\n", partition.Mountpoint, err)
			continue
		}

		// Utwórz i wypełnij strukturę Disk
		disk := models.Disk{
			Device:     partition.Device,
			Mountpoint: partition.Mountpoint,
			Fstype:     partition.Fstype,
			TotalGB:    toGB(usage.Total),
			UsedGB:     toGB(usage.Used),
			FreeGB:     toGB(usage.Free),
			Percent:    usage.UsedPercent,
		}

		disks = append(disks, disk)
	}

	hardware.Disks = disks

	return nil
}

// collectNetworkInfo zbiera informacje o interfejsach sieciowych
func (c *HardwareCollector) collectNetworkInfo(hardware *models.Hardware) error {
	// Pobierz interfejsy sieciowe
	interfaces, err := net.Interfaces()
	if err != nil {
		return fmt.Errorf("nie można pobrać informacji o interfejsach sieciowych: %v", err)
	}

	// Pobierz statystyki IO
	ioStats, err := net.IOCounters(true)
	if err != nil {
		return fmt.Errorf("nie można pobrać statystyk IO: %v", err)
	}

	// Utwórz mapę na informacje o interfejsach
	networkMap := make(map[string]models.NetworkInterface)

	// Zbierz informacje o każdym interfejsie
	for _, iface := range interfaces {
		// Pomiń interfejsy loopback i bez adresów
		if iface.Flags&net.FlagLoopback != 0 || len(iface.Addrs) == 0 {
			continue
		}

		// Zbierz adresy IP
		addresses := make([]string, 0, len(iface.Addrs))
		for _, addr := range iface.Addrs {
			addresses = append(addresses, addr.Addr)
		}

		// Utwórz i wypełnij strukturę NetworkInterface
		networkInterface := models.NetworkInterface{
			Name:      iface.Name,
			MAC:       iface.HardwareAddr,
			Addresses: addresses,
			Flags:     iface.Flags.String(),
		}

		// Dodaj statystyki IO, jeśli są dostępne
		for _, stat := range ioStats {
			if stat.Name == iface.Name {
				networkInterface.BytesSent = stat.BytesSent
				networkInterface.BytesRecv = stat.BytesRecv
				networkInterface.PacketsSent = stat.PacketsSent
				networkInterface.PacketsRecv = stat.PacketsRecv
				networkInterface.Errin = stat.Errin
				networkInterface.Errout = stat.Errout
				networkInterface.Dropin = stat.Dropin
				networkInterface.Dropout = stat.Dropout
				break
			}
		}

		networkMap[iface.Name] = networkInterface
	}

	hardware.Network = networkMap

	return nil
}

// collectGPUInfo zbiera informacje o kartach graficznych NVIDIA
func (c *HardwareCollector) collectGPUInfo(hardware *models.Hardware) error {
	// Inicjalizuj NVML
	ret := nvml.Init()
	if ret != nvml.SUCCESS {
		// Jeśli inicjalizacja się nie powiedzie, zwróć błąd, ale nie przerywaj
		return fmt.Errorf("nie można zainicjować NVML: %v", nvml.ErrorString(ret))
	}
	defer nvml.Shutdown()

	// Pobierz liczbę urządzeń
	count, ret := nvml.DeviceGetCount()
	if ret != nvml.SUCCESS {
		return fmt.Errorf("nie można pobrać liczby urządzeń GPU: %v", nvml.ErrorString(ret))
	}

	// Jeśli nie ma urządzeń, zakończ
	if count == 0 {
		return nil
	}

	// Utwórz mapę na informacje o GPU
	gpuMap := make(map[string][]models.GPUDevice)
	gpuMap["nvidia"] = make([]models.GPUDevice, 0, count)

	// Zbierz informacje o każdym urządzeniu
	for i := 0; i < count; i++ {
		// Pobierz uchwyt do urządzenia
		device, ret := nvml.DeviceGetHandleByIndex(i)
		if ret != nvml.SUCCESS {
			fmt.Printf("Ostrzeżenie: nie można pobrać uchwytu dla GPU %d: %v\n", i, nvml.ErrorString(ret))
			continue
		}

		// Pobierz nazwę urządzenia
		name, ret := device.GetName()
		if ret != nvml.SUCCESS {
			fmt.Printf("Ostrzeżenie: nie można pobrać nazwy dla GPU %d: %v\n", i, nvml.ErrorString(ret))
			name = "Unknown NVIDIA GPU"
		}

		// Pobierz temperaturę
		temp, ret := device.GetTemperature(nvml.TEMPERATURE_GPU)
		if ret != nvml.SUCCESS {
			fmt.Printf("Ostrzeżenie: nie można pobrać temperatury dla GPU %d: %v\n", i, nvml.ErrorString(ret))
			temp = 0
		}

		// Pobierz wykorzystanie GPU
		utilization, ret := device.GetUtilizationRates()
		if ret != nvml.SUCCESS {
			fmt.Printf("Ostrzeżenie: nie można pobrać wykorzystania dla GPU %d: %v\n", i, nvml.ErrorString(ret))
			utilization.Gpu = 0
		}

		// Pobierz informacje o pamięci
		memory, ret := device.GetMemoryInfo()
		if ret != nvml.SUCCESS {
			fmt.Printf("Ostrzeżenie: nie można pobrać informacji o pamięci dla GPU %d: %v\n", i, nvml.ErrorString(ret))
			memory.Total = 0
			memory.Used = 0
		}

		// Konwertuj bajty na MB
		toMB := func(bytes uint64) float64 {
			return float64(bytes) / (1024 * 1024)
		}

		// Utwórz i wypełnij strukturę GPUDevice
		gpuDevice := models.GPUDevice{
			Index:           i,
			Name:            name,
			Temperature:     float64(temp),
			UtilizationGPU:  float64(utilization.Gpu),
			MemoryUsedMB:    toMB(memory.Used),
			MemoryTotalMB:   toMB(memory.Total),
		}

		gpuMap["nvidia"] = append(gpuMap["nvidia"], gpuDevice)
	}

	hardware.GPU = gpuMap

	return nil
}
