package utils

import (
	"encoding/json"
	"fmt"
	"os"
)

// Config reprezentuje konfigurację agenta
type Config struct {
	Interval         int    `json:"interval"`         // Interwał zbierania danych w sekundach
	BridgeURL        string `json:"bridge_url"`        // URL do VM Bridge
	LogFile          string `json:"log_file"`          // Ścieżka do pliku logów
	StateDir         string `json:"state_dir"`         // Katalog na pliki stanów
	IncludeProcesses bool   `json:"include_processes"` // Czy zbierać informacje o procesach
	Verbose          bool   `json:"verbose"`           // Tryb szczegółowego logowania
}

// LoadConfig wczytuje konfigurację z pliku JSON
func LoadConfig(path string) (*Config, error) {
	// Wczytaj plik konfiguracyjny
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("nie można odczytać pliku konfiguracyjnego: %v", err)
	}

	// Parsuj JSON
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("nie można sparsować pliku konfiguracyjnego: %v", err)
	}

	// Sprawdź poprawność konfiguracji
	if config.Interval <= 0 {
		config.Interval = 10 // Domyślny interwał 10 sekund
	}

	if config.BridgeURL == "" {
		config.BridgeURL = "http://localhost:5678/api/v1/update_state" // Domyślny URL
	}

	if config.LogFile == "" {
		config.LogFile = "/var/log/safetytwin/agent.log" // Domyślna ścieżka logów
	}

	if config.StateDir == "" {
		config.StateDir = "/var/lib/safetytwin/agent-states" // Domyślny katalog stanów
	}

	return &config, nil
}

// SaveConfig zapisuje konfigurację do pliku JSON
func SaveConfig(config *Config, path string) error {
	// Serializuj konfigurację do JSON
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("nie można serializować konfiguracji: %v", err)
	}

	// Zapisz do pliku
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("nie można zapisać pliku konfiguracyjnego: %v", err)
	}

	return nil
}
