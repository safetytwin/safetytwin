package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"gitlab.com/safetytwin/safetytwin/agent/collectors"
	"gitlab.com/safetytwin/safetytwin/agent/models"
	"gitlab.com/safetytwin/safetytwin/agent/utils"
)

// Informacje o wersji
const (
	VERSION = "1.0.0"
	AUTHOR  = "SafetyTwin System"
)

func main() {
	// Wyświetl banner
	log.Printf("SafetyTwin Agent v%s", VERSION)
	// Parsowanie flag wiersza poleceń
	configPath := flag.String("config", "", "Ścieżka do pliku konfiguracyjnego")
	outputFile := flag.String("output", "", "Plik wyjściowy dla danych JSON (opcjonalny)")
	pretty := flag.Bool("pretty", false, "Formatuj JSON w sposób czytelny dla człowieka")
	version := flag.Bool("version", false, "Wyświetl informacje o wersji i zakończ")
	flag.Parse()

	// Wyświetl wersję i zakończ, jeśli podano flagę -version
	if *version {
		fmt.Printf("SafetyTwin Agent v%s\n", VERSION)
		fmt.Printf("Copyright (c) 2025 %s\n", AUTHOR)
		os.Exit(0)
	}

	// Tryb jednorazowy (dla pliku wyjściowego)
	if *outputFile != "" {
		runSingleCollection(*outputFile, *pretty)
		return
	}

	// Wczytanie konfiguracji
	var config *utils.Config
	var err error

	if *configPath != "" {
		config, err = utils.LoadConfig(*configPath)
		if err != nil {
			log.Fatalf("Błąd wczytywania konfiguracji: %v", err)
		}
	} else {
		// Domyślna konfiguracja
		config = &utils.Config{
			Interval:         10,
			BridgeURL:        "http://localhost:5678/api/v1/update_state",
			LogFile:          "/var/log/safetytwin/agent.log",
			StateDir:         "/var/lib/safetytwin/agent-states",
			IncludeProcesses: true,
			Verbose:          false,
		}
	}

	// Upewnij się, że katalogi istnieją
	stateDir := filepath.Dir(config.StateDir)
	logDir := filepath.Dir(config.LogFile)
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		log.Fatalf("Nie można utworzyć katalogu stanów: %v", err)
	}
	if err := os.MkdirAll(logDir, 0755); err != nil {
		log.Fatalf("Nie można utworzyć katalogu logów: %v", err)
	}

	// Konfiguracja loggera
	utils.ConfigureLogger(config.LogFile, config.Verbose)

	// Przygotowanie nadawcy danych
	sender := utils.NewSender(config.BridgeURL)

	// Obsługa sygnałów
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	stopChan := make(chan struct{})

	// Uruchom proces zbierania danych w osobnym wątku
	go runDataCollection(config, sender, stopChan)

	// Czekaj na sygnał zakończenia
	sig := <-sigChan
	log.Printf("Otrzymano sygnał: %v. Kończenie działania...", sig)
	close(stopChan)

	// Daj czas na zakończenie wątków
	time.Sleep(500 * time.Millisecond)
	log.Println("Agent zakończył działanie")
}

// runSingleCollection wykonuje jednorazowe zbieranie danych i zapisuje je do pliku
func runSingleCollection(outputFile string, pretty bool) {
	fmt.Println("Rozpoczynam zbieranie informacji o systemie...")
	startTime := time.Now()

	// Utwórz kolektor systemu
	systemCollector := collectors.NewSystemCollector()

	// Zbierz informacje o systemie
	systemState, err := systemCollector.Collect()
	if err != nil {
		fmt.Printf("Błąd podczas zbierania informacji o systemie: %v\n", err)
		os.Exit(1)
	}

	elapsedTime := time.Since(startTime)
	fmt.Printf("Zbieranie informacji zakończone w %v\n\n", elapsedTime)

	// Wyświetl podstawowe informacje
	fmt.Println("Podstawowe informacje o systemie:")
	fmt.Printf("Hostname: %s\n", systemState.Hardware.Hostname)
	fmt.Printf("Platform: %s %s\n", systemState.Hardware.Platform, systemState.Hardware.PlatformVersion)
	fmt.Printf("Kernel: %s\n", systemState.Hardware.KernelVersion)
	fmt.Printf("CPU: %s (%d rdzeni fizycznych, %d rdzeni logicznych)\n", 
		systemState.Hardware.CPU.Model, 
		systemState.Hardware.CPU.PhysicalCores, 
		systemState.Hardware.CPU.LogicalCores)
	fmt.Printf("Pamięć: %.2f GB (użycie: %.1f%%)\n", 
		systemState.Hardware.Memory.TotalGB, 
		systemState.Hardware.Memory.Percent)
	fmt.Printf("Liczba dysków: %d\n", len(systemState.Hardware.Disks))
	fmt.Printf("Liczba interfejsów sieciowych: %d\n", len(systemState.Hardware.Network))
	fmt.Printf("Liczba procesów: %d\n", len(systemState.Processes))
	fmt.Printf("Liczba usług: %d\n", len(systemState.Services))

	// Policz procesy i usługi związane z LLM
	llmProcesses := 0
	for _, proc := range systemState.Processes {
		if proc.IsLLMRelated {
			llmProcesses++
		}
	}

	llmServices := 0
	for _, svc := range systemState.Services {
		if svc.IsLLMRelated {
			llmServices++
		}
	}

	fmt.Printf("Procesy związane z LLM: %d\n", llmProcesses)
	fmt.Printf("Usługi związane z LLM: %d\n", llmServices)

	// Zapisz dane do pliku
	var jsonData []byte

	if pretty {
		jsonData, err = json.MarshalIndent(systemState, "", "  ")
	} else {
		jsonData, err = json.Marshal(systemState)
	}

	if err != nil {
		fmt.Printf("Błąd podczas serializacji do JSON: %v\n", err)
		os.Exit(1)
	}

	err = os.WriteFile(outputFile, jsonData, 0644)
	if err != nil {
		fmt.Printf("Błąd podczas zapisywania do pliku: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Dane zapisane do pliku: %s\n", outputFile)
}

// runDataCollection uruchamia proces zbierania danych w pętli
func runDataCollection(config *utils.Config, sender *utils.Sender, stopChan <-chan struct{}) {
	// Interwał zbierania danych
	interval := time.Duration(config.Interval) * time.Second
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	log.Printf("Agent uruchomiony. Interwał zbierania danych: %d sekund", config.Interval)

	// Natychmiastowe pierwsze zbieranie
	collectAndSendState(config, sender)

	// Główna pętla zbierania danych
	for {
		select {
		case <-ticker.C:
			collectAndSendState(config, sender)
		case <-stopChan:
			log.Println("Zatrzymanie procesu zbierania danych")
			return
		}
	}
}

// collectAndSendState zbiera i wysyła stan systemu
func collectAndSendState(config *utils.Config, sender *utils.Sender) {
	startTime := time.Now()
	log.Println("Rozpoczęcie zbierania danych o systemie...")

	// Utwórz kolektor systemu
	systemCollector := collectors.NewSystemCollector()

	// Zbierz informacje o systemie
	systemState, err := systemCollector.Collect()
	if err != nil {
		log.Printf("Błąd podczas zbierania informacji o systemie: %v", err)
		return
	}

	// Zapisanie stanu do pliku
	if err := utils.SaveStateToFile(systemState, config.StateDir); err != nil {
		log.Printf("Błąd zapisu stanu do pliku: %v", err)
	}

	// Wysłanie stanu do VM Bridge
	if err := sender.SendState(systemState); err != nil {
		log.Printf("Błąd wysyłania stanu do VM Bridge: %v", err)
	} else {
		log.Printf("Stan systemu pomyślnie wysłany do VM Bridge")
	}

	// Raportuj czas trwania
	elapsedTime := time.Since(startTime)
	log.Printf("Zbieranie danych zakończone. Czas trwania: %v", elapsedTime)
}
