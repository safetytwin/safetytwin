package utils

import (
	"digital-twin/agent/models"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSaveStateToFile(t *testing.T) {
	// Utwórz tymczasowy katalog na pliki testowe
	tempDir := t.TempDir()
	
	// Utwórz testowy stan
	state := &models.SystemState{
		Hostname:  "test-host",
		Timestamp: time.Now().Unix(),
		CPU: &models.CPUInfo{
			Usage: 50.0,
		},
		Memory: &models.MemoryInfo{
			Total:     8192,
			Used:      4096,
			Available: 4096,
		},
	}
	
	// Zapisz stan do pliku
	err := SaveStateToFile(state, tempDir)
	if err != nil {
		t.Fatalf("Błąd podczas zapisywania stanu: %v", err)
	}
	
	// Sprawdź, czy plik został utworzony
	files, err := os.ReadDir(tempDir)
	if err != nil {
		t.Fatalf("Błąd podczas odczytu katalogu: %v", err)
	}
	
	if len(files) != 1 {
		t.Fatalf("Niepoprawna liczba plików: got %v, want 1", len(files))
	}
	
	// Sprawdź, czy nazwa pliku jest poprawna
	fileName := files[0].Name()
	if !filepath.Ext(fileName) == ".json" {
		t.Errorf("Niepoprawne rozszerzenie pliku: got %v, want .json", filepath.Ext(fileName))
	}
	
	// Odczytaj plik i sprawdź zawartość
	filePath := filepath.Join(tempDir, fileName)
	fileData, err := os.ReadFile(filePath)
	if err != nil {
		t.Fatalf("Błąd podczas odczytu pliku: %v", err)
	}
	
	var loadedState models.SystemState
	err = json.Unmarshal(fileData, &loadedState)
	if err != nil {
		t.Fatalf("Błąd podczas deserializacji JSON: %v", err)
	}
	
	// Sprawdź, czy dane są poprawne
	if loadedState.Hostname != state.Hostname {
		t.Errorf("Niepoprawna nazwa hosta: got %v, want %v", loadedState.Hostname, state.Hostname)
	}
	if loadedState.Timestamp != state.Timestamp {
		t.Errorf("Niepoprawny znacznik czasu: got %v, want %v", loadedState.Timestamp, state.Timestamp)
	}
	if loadedState.CPU.Usage != state.CPU.Usage {
		t.Errorf("Niepoprawne użycie CPU: got %v, want %v", loadedState.CPU.Usage, state.CPU.Usage)
	}
}

func TestCleanupOldStateFiles(t *testing.T) {
	// Utwórz tymczasowy katalog na pliki testowe
	tempDir := t.TempDir()
	
	// Utwórz kilka plików stanów z różnymi czasami modyfikacji
	fileCount := 15
	maxFiles := 10
	
	for i := 0; i < fileCount; i++ {
		fileName := filepath.Join(tempDir, fmt.Sprintf("state_%d.json", i))
		
		// Utwórz plik
		err := os.WriteFile(fileName, []byte("{}"), 0644)
		if err != nil {
			t.Fatalf("Błąd podczas tworzenia pliku testowego: %v", err)
		}
		
		// Ustaw czas modyfikacji
		modTime := time.Now().Add(-time.Duration(fileCount-i) * time.Hour)
		err = os.Chtimes(fileName, modTime, modTime)
		if err != nil {
			t.Fatalf("Błąd podczas ustawiania czasu modyfikacji: %v", err)
		}
	}
	
	// Wywołaj funkcję czyszczenia
	err := cleanupOldStateFiles(tempDir, maxFiles)
	if err != nil {
		t.Fatalf("Błąd podczas czyszczenia starych plików: %v", err)
	}
	
	// Sprawdź, czy pozostała poprawna liczba plików
	files, err := os.ReadDir(tempDir)
	if err != nil {
		t.Fatalf("Błąd podczas odczytu katalogu: %v", err)
	}
	
	if len(files) != maxFiles {
		t.Errorf("Niepoprawna liczba plików po czyszczeniu: got %v, want %v", len(files), maxFiles)
	}
	
	// Sprawdź, czy pozostały najnowsze pliki
	for i := 0; i < len(files); i++ {
		expectedName := fmt.Sprintf("state_%d.json", i+fileCount-maxFiles)
		found := false
		
		for _, file := range files {
			if file.Name() == expectedName {
				found = true
				break
			}
		}
		
		if !found {
			t.Errorf("Nie znaleziono oczekiwanego pliku: %s", expectedName)
		}
	}
}
