package utils

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfig(t *testing.T) {
	// Utwórz tymczasowy katalog na pliki testowe
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "agent-config.json")

	// Test wczytywania domyślnej konfiguracji, gdy plik nie istnieje
	config, err := LoadConfig(configPath)
	if err != nil {
		t.Fatalf("Błąd podczas wczytywania konfiguracji: %v", err)
	}

	// Sprawdź, czy domyślne wartości są poprawne
	if config.Interval != 10 {
		t.Errorf("Niepoprawny interwał: got %v, want 10", config.Interval)
	}
	if config.BridgeURL != "http://localhost:5678/api/v1/update_state" {
		t.Errorf("Niepoprawny URL: got %v, want http://localhost:5678/api/v1/update_state", config.BridgeURL)
	}
	if config.LogFile != "/var/log/digital-twin-agent.log" {
		t.Errorf("Niepoprawny plik dziennika: got %v, want /var/log/digital-twin-agent.log", config.LogFile)
	}
	if config.StateDir != "/var/lib/digital-twin/states" {
		t.Errorf("Niepoprawny katalog stanów: got %v, want /var/lib/digital-twin/states", config.StateDir)
	}
	if !config.IncludeProcesses {
		t.Errorf("Niepoprawna wartość IncludeProcesses: got %v, want true", config.IncludeProcesses)
	}
	if !config.IncludeNetwork {
		t.Errorf("Niepoprawna wartość IncludeNetwork: got %v, want true", config.IncludeNetwork)
	}
	if config.Verbose {
		t.Errorf("Niepoprawna wartość Verbose: got %v, want false", config.Verbose)
	}

	// Sprawdź, czy plik został utworzony
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		t.Errorf("Plik konfiguracyjny nie został utworzony")
	}

	// Test wczytywania niestandardowej konfiguracji
	customConfig := &Config{
		Interval:         30,
		BridgeURL:        "http://example.com/api",
		LogFile:          "/tmp/agent.log",
		StateDir:         "/tmp/states",
		IncludeProcesses: false,
		IncludeNetwork:   false,
		Verbose:          true,
	}

	// Zapisz niestandardową konfigurację
	if err := SaveConfig(customConfig, configPath); err != nil {
		t.Fatalf("Błąd podczas zapisywania konfiguracji: %v", err)
	}

	// Wczytaj konfigurację ponownie
	loadedConfig, err := LoadConfig(configPath)
	if err != nil {
		t.Fatalf("Błąd podczas wczytywania konfiguracji: %v", err)
	}

	// Sprawdź, czy wartości są poprawne
	if loadedConfig.Interval != customConfig.Interval {
		t.Errorf("Niepoprawny interwał: got %v, want %v", loadedConfig.Interval, customConfig.Interval)
	}
	if loadedConfig.BridgeURL != customConfig.BridgeURL {
		t.Errorf("Niepoprawny URL: got %v, want %v", loadedConfig.BridgeURL, customConfig.BridgeURL)
	}
	if loadedConfig.LogFile != customConfig.LogFile {
		t.Errorf("Niepoprawny plik dziennika: got %v, want %v", loadedConfig.LogFile, customConfig.LogFile)
	}
	if loadedConfig.StateDir != customConfig.StateDir {
		t.Errorf("Niepoprawny katalog stanów: got %v, want %v", loadedConfig.StateDir, customConfig.StateDir)
	}
	if loadedConfig.IncludeProcesses != customConfig.IncludeProcesses {
		t.Errorf("Niepoprawna wartość IncludeProcesses: got %v, want %v", loadedConfig.IncludeProcesses, customConfig.IncludeProcesses)
	}
	if loadedConfig.IncludeNetwork != customConfig.IncludeNetwork {
		t.Errorf("Niepoprawna wartość IncludeNetwork: got %v, want %v", loadedConfig.IncludeNetwork, customConfig.IncludeNetwork)
	}
	if loadedConfig.Verbose != customConfig.Verbose {
		t.Errorf("Niepoprawna wartość Verbose: got %v, want %v", loadedConfig.Verbose, customConfig.Verbose)
	}
}

func TestSaveConfig(t *testing.T) {
	// Utwórz tymczasowy katalog na pliki testowe
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "subdir", "agent-config.json")

	// Utwórz konfigurację do zapisania
	config := &Config{
		Interval:         20,
		BridgeURL:        "http://test.com/api",
		LogFile:          "/var/log/test.log",
		StateDir:         "/var/lib/test",
		IncludeProcesses: true,
		IncludeNetwork:   false,
		Verbose:          true,
	}

	// Zapisz konfigurację
	err := SaveConfig(config, configPath)
	if err != nil {
		t.Fatalf("Błąd podczas zapisywania konfiguracji: %v", err)
	}

	// Sprawdź, czy plik został utworzony
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		t.Errorf("Plik konfiguracyjny nie został utworzony")
	}

	// Odczytaj plik i sprawdź zawartość
	fileData, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("Błąd podczas odczytu pliku: %v", err)
	}

	var loadedConfig Config
	err = json.Unmarshal(fileData, &loadedConfig)
	if err != nil {
		t.Fatalf("Błąd podczas deserializacji JSON: %v", err)
	}

	// Sprawdź, czy wartości są poprawne
	if loadedConfig.Interval != config.Interval {
		t.Errorf("Niepoprawny interwał: got %v, want %v", loadedConfig.Interval, config.Interval)
	}
	if loadedConfig.BridgeURL != config.BridgeURL {
		t.Errorf("Niepoprawny URL: got %v, want %v", loadedConfig.BridgeURL, config.BridgeURL)
	}
	if loadedConfig.LogFile != config.LogFile {
		t.Errorf("Niepoprawny plik dziennika: got %v, want %v", loadedConfig.LogFile, config.LogFile)
	}
	if loadedConfig.StateDir != config.StateDir {
		t.Errorf("Niepoprawny katalog stanów: got %v, want %v", loadedConfig.StateDir, config.StateDir)
	}
	if loadedConfig.IncludeProcesses != config.IncludeProcesses {
		t.Errorf("Niepoprawna wartość IncludeProcesses: got %v, want %v", loadedConfig.IncludeProcesses, config.IncludeProcesses)
	}
	if loadedConfig.IncludeNetwork != config.IncludeNetwork {
		t.Errorf("Niepoprawna wartość IncludeNetwork: got %v, want %v", loadedConfig.IncludeNetwork, config.IncludeNetwork)
	}
	if loadedConfig.Verbose != config.Verbose {
		t.Errorf("Niepoprawna wartość Verbose: got %v, want %v", loadedConfig.Verbose, config.Verbose)
	}
}
