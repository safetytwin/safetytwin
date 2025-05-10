package utils

import (
	"digital-twin/agent/models"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// SaveStateToFile zapisuje stan systemu do pliku JSON
func SaveStateToFile(state *models.SystemState, stateDir string) error {
	// Utwórz katalog stanów, jeśli nie istnieje
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return fmt.Errorf("nie można utworzyć katalogu stanów: %v", err)
	}

	// Wygeneruj nazwę pliku na podstawie znacznika czasu
	timestamp := time.Now().Format("20060102_150405")
	stateFile := filepath.Join(stateDir, fmt.Sprintf("state_%s.json", timestamp))

	// Serializuj stan do JSON
	jsonData, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("błąd podczas serializacji stanu: %v", err)
	}

	// Zapisz do pliku
	if err := os.WriteFile(stateFile, jsonData, 0644); err != nil {
		return fmt.Errorf("błąd podczas zapisywania stanu do pliku: %v", err)
	}

	// Usuń stare pliki stanów, jeśli jest ich za dużo
	if err := cleanupOldStateFiles(stateDir, 10); err != nil {
		return fmt.Errorf("błąd podczas czyszczenia starych plików stanów: %v", err)
	}

	return nil
}

// cleanupOldStateFiles usuwa stare pliki stanów, pozostawiając tylko maxFiles najnowszych
func cleanupOldStateFiles(stateDir string, maxFiles int) error {
	// Pobierz listę plików w katalogu stanów
	files, err := os.ReadDir(stateDir)
	if err != nil {
		return err
	}

	// Filtruj tylko pliki stanów
	stateFiles := []string{}
	for _, file := range files {
		if !file.IsDir() && filepath.Ext(file.Name()) == ".json" {
			stateFiles = append(stateFiles, filepath.Join(stateDir, file.Name()))
		}
	}

	// Jeśli liczba plików nie przekracza maksymalnej, nie rób nic
	if len(stateFiles) <= maxFiles {
		return nil
	}

	// Pobierz informacje o plikach
	type fileInfo struct {
		path    string
		modTime time.Time
	}
	fileInfos := make([]fileInfo, 0, len(stateFiles))
	for _, path := range stateFiles {
		info, err := os.Stat(path)
		if err != nil {
			continue
		}
		fileInfos = append(fileInfos, fileInfo{path, info.ModTime()})
	}

	// Sortuj pliki według czasu modyfikacji (od najstarszego do najnowszego)
	sortFileInfos(fileInfos)

	// Usuń najstarsze pliki, pozostawiając tylko maxFiles najnowszych
	for i := 0; i < len(fileInfos)-maxFiles; i++ {
		if err := os.Remove(fileInfos[i].path); err != nil {
			return err
		}
	}

	return nil
}

// sortFileInfos sortuje pliki według czasu modyfikacji (od najstarszego do najnowszego)
func sortFileInfos(files []fileInfo) {
	for i := 0; i < len(files); i++ {
		for j := i + 1; j < len(files); j++ {
			if files[i].modTime.After(files[j].modTime) {
				files[i], files[j] = files[j], files[i]
			}
		}
	}
}
