package utils

import (
	"encoding/json"
	"fmt"
	"os"
)

// Config przechowuje konfigurację agenta
type Config struct {
	Interval         int    `json:"interval"`          // Interwał odczytu w sekundach
	BridgeURL        string `json:"bridge_url"`        // URL do VM Bridge
	LogFile          string `json:"log_file"`          // Plik dziennika
	StateDir         string `json:"state_dir"`         // Katalog na dane stanu
	IncludeProcesses bool   `json:"include_processes"` // Czy zbierać dane o procesach
	IncludeNetwork   bool   `json:"include_network"`   // Czy zbierać dane o sieci
	Verbose          bool   `json:"verbose"`           // Tryb szczegółowego logowania
}

// LoadConfig wczytuje konfigurację z pliku JSON
func LoadConfig(configPath string) (*Config, error) {
	// Domyślna konfiguracja
	config := &Config{
		Interval:         10,
		BridgeURL:        "http://localhost:5678/api/v1/update_state",
		LogFile:          "/var/log/digital-twin-agent.log",
		StateDir:         "/var/lib/digital-twin/states",
		IncludeProcesses: true,
		IncludeNetwork:   true,
		Verbose:          false,
	}

	// Sprawdź, czy plik konfiguracyjny istnieje
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Zapisz domyślną konfigurację do pliku
		if err := SaveConfig(config, configPath); err != nil {
			return nil, fmt.Errorf("nie można zapisać domyślnej konfiguracji: %v", err)
		}
		return config, nil
	}

	// Wczytaj konfigurację z pliku
	file, err := os.Open(configPath)
	if err != nil {
		return nil, fmt.Errorf("nie można otworzyć pliku konfiguracyjnego: %v", err)
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	if err := decoder.Decode(config); err != nil {
		return nil, fmt.Errorf("błąd podczas dekodowania pliku konfiguracyjnego: %v", err)
	}

	return config, nil
}

// SaveConfig zapisuje konfigurację do pliku JSON
func SaveConfig(config *Config, configPath string) error {
	// Utwórz katalog, jeśli nie istnieje
	dir := configPath[:len(configPath)-len("/agent-config.json")]
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("nie można utworzyć katalogu konfiguracyjnego: %v", err)
	}

	// Serializuj konfigurację do JSON
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("błąd podczas serializacji konfiguracji: %v", err)
	}

	// Zapisz do pliku
	if err := os.WriteFile(configPath, data, 0644); err != nil {
		return fmt.Errorf("nie można zapisać pliku konfiguracyjnego: %v", err)
	}

	return nil
}
