package utils

import (
	"safetytwin/agent/models"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// SaveStateToFile zapisuje stan systemu do pliku JSON
func SaveStateToFile(state *models.SystemState, stateDir string) error {
	// Utwórz katalog stanów, jeśli nie istnieje
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return fmt.Errorf("nie można utworzyć katalogu stanów %s: %w", stateDir, err)
	}

	// Wygeneruj nazwę pliku na podstawie znacznika czasu
	timestamp := time.Now().Format("20060102_150405")
	stateFile := filepath.Join(stateDir, fmt.Sprintf("state_%s.json", timestamp))

	// Serializuj stan do JSON
	jsonData, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("błąd podczas serializacji stanu: %w", err)
	}

	// Zapisz do pliku
	if err := os.WriteFile(stateFile, jsonData, 0644); err != nil {
		return fmt.Errorf("błąd podczas zapisywania stanu do pliku %s: %w", stateFile, err)
	}

	// Usuń stare pliki stanów, jeśli jest ich za dużo
	if err := cleanupOldStateFiles(stateDir, 10); err != nil {
		return fmt.Errorf("błąd podczas czyszczenia starych plików stanów w %s: %w", stateDir, err)
	}

	return nil
}

// cleanupOldStateFiles usuwa stare pliki stanów, pozostawiając tylko maxFiles najnowszych
func cleanupOldStateFiles(stateDir string, maxFiles int) error {
	// Pobierz listę plików w katalogu stanów
	files, err := os.ReadDir(stateDir)
	if err != nil {
		return fmt.Errorf("nie można odczytać katalogu stanów %s: %w", stateDir, err)
	}

	// Filtruj tylko pliki stanów
	type fileInfo struct {
		path    string
		modTime time.Time
	}
	
	var fileInfos []fileInfo
	for _, file := range files {
		if !file.IsDir() && filepath.Ext(file.Name()) == ".json" {
			path := filepath.Join(stateDir, file.Name())
			info, err := os.Stat(path)
			if err != nil {
				continue
			}
			fileInfos = append(fileInfos, fileInfo{path, info.ModTime()})
		}
	}

	// Jeśli liczba plików nie przekracza maksymalnej, nie rób nic
	if len(fileInfos) <= maxFiles {
		return nil
	}

	// Sortuj pliki według czasu modyfikacji (od najstarszego do najnowszego)
	sort.Slice(fileInfos, func(i, j int) bool {
		return fileInfos[i].modTime.Before(fileInfos[j].modTime)
	})

	// Usuń najstarsze pliki, pozostawiając tylko maxFiles najnowszych
	for i := 0; i < len(fileInfos)-maxFiles; i++ {
		if err := os.Remove(fileInfos[i].path); err != nil {
			return fmt.Errorf("nie można usunąć starego pliku stanu %s: %w", fileInfos[i].path, err)
		}
	}

	return nil
}
