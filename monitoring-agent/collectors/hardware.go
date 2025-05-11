package collectors

import (
	"safetytwin/agent/models"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	"runtime"
	"time"
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
	}

	// Informacje o CPU
	hardware.CPU = &models.CPU{}
	if cpuInfo, err := cpu.Info(); err == nil && len(cpuInfo) > 0 {
		hardware.CPU.Model = cpuInfo[0].ModelName
		hardware.CPU.PhysicalCores = cpuInfo[0].Cores
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

	return hardware, nil
}
