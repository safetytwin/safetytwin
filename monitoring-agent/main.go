package main

import (
	"safetytwin/agent/collectors"
	"safetytwin/agent/models"
	"safetytwin/agent/utils"
	"flag"
	"log"
	"time"
)

func main() {
	// Parsowanie flag wiersza poleceń
	configPath := flag.String("config", "agent-config.json", "Ścieżka do pliku konfiguracyjnego")
	flag.Parse()

	// Wczytanie konfiguracji
	config, err := utils.LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("Błąd wczytywania konfiguracji: %v", err)
	}

	// Konfiguracja loggera
	utils.ConfigureLogger(config.LogFile, config.Verbose)

	// Przygotowanie nadawcy danych
	sender := utils.NewSender(config.BridgeURL)

	// Główna pętla zbierania danych
	ticker := time.NewTicker(time.Duration(config.Interval) * time.Second)
	defer ticker.Stop()

	log.Printf("Agent uruchomiony. Interwał zbierania danych: %d sekund", config.Interval)

	// Natychmiastowe pierwsze zbieranie
	collectAndSendState(config, sender)

	// Pętla zbierania danych
	for {
		select {
		case <-ticker.C:
			collectAndSendState(config, sender)
		}
	}
}

// Zbieranie i wysyłanie stanu systemu
func collectAndSendState(config *utils.Config, sender *utils.Sender) {
	// Tworzenie obiektu stanu systemu
	state := models.SystemState{
		Timestamp: time.Now().Format(time.RFC3339),
	}

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
	if err := utils.SaveStateToFile(&state, config.StateDir); err != nil {
		log.Printf("Błąd zapisu stanu do pliku: %v", err)
	}

	// Wysłanie stanu do VM Bridge
	if err := sender.SendState(&state); err != nil {
		log.Printf("Błąd wysyłania stanu do VM Bridge: %v", err)
	} else {
		log.Printf("Stan systemu pomyślnie wysłany do VM Bridge")
	}
}
