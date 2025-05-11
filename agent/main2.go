package main

import (
	"safetytwin/agent/collectors"
	"safetytwin/agent/models"
	"safetytwin/agent/utils"
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

// Informacje o wersji
const (
	VERSION = "1.0.0"
	AUTHOR  = "Digital Twin System"
)

func main() {
	// Wyświetl banner
	log.Printf("Digital Twin Agent v%s", VERSION)
	log.Printf("Copyright (c) 2025 %s", AUTHOR)

	// Parsowanie flag wiersza poleceń
	configPath := flag.String("config", "/etc/safetytwin/agent-config.json", "Ścieżka do pliku konfiguracyjnego")
	version := flag.Bool("version", false, "Wyświetl informacje o wersji i zakończ")
	flag.Parse()

	// Wyświetl wersję i zakończ, jeśli podano flagę -version
	if *version {
		os.Exit(0)
	}

	// Wczytanie konfiguracji
	config, err := utils.LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("Błąd wczytywania konfiguracji: %v", err)
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

	// Tworzenie obiektu stanu systemu
	state := models.NewSystemState()

	// Zbieranie danych o sprzęcie
	hardware, err := collectors.CollectHardwareInfo()
	if err != nil {
		log.Printf("Błąd podczas zbierania informacji o sprzęcie: %v", err)
	} else {
		state.Hardware = hardware
	}

	// Zbieranie danych o usługach
	services, err := collectors.CollectServicesInfo()
	if err != nil {
		log.Printf("Błąd podczas zbierania informacji o usługach: %v", err)
	} else {
		state.Services = services
	}

	// Zbieranie danych o procesach (opcjonalnie)
	if config.IncludeProcesses {
		processes, err := collectors.CollectProcessesInfo()
		if err != nil {
			log.Printf("Błąd podczas zbierania informacji o procesach: %v", err)
		} else {
			state.Processes = processes
		}
	}

	// Zapisanie stanu do pliku
	if err := utils.SaveStateToFile(state, config.StateDir); err != nil {
		log.Printf("Błąd zapisu stanu do pliku: %v", err)
	}

	// Wysłanie stanu do VM Bridge
	if err := sender.SendState(state); err != nil {
		log.Printf("Błąd wysyłania stanu do VM Bridge: %v", err)
	} else {
		log.Printf("Stan systemu pomyślnie wysłany do VM Bridge")
	}

	// Raportuj czas trwania
	elapsedTime := time.Since(startTime)
	log.Printf("Zbieranie danych zakończone. Czas trwania: %v", elapsedTime)
}