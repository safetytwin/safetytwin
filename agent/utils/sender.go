package utils

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"gitlab.com/safetytwin/safetytwin/agent/models"
)

// Sender odpowiada za wysyłanie danych do VM Bridge
type Sender struct {
	URL        string
	HTTPClient *http.Client
}

// NewSender tworzy nowy obiekt Sender
func NewSender(url string) *Sender {
	return &Sender{
		URL: url,
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// SendState wysyła stan systemu do VM Bridge
func (s *Sender) SendState(state *models.SystemState) error {
	// Serializuj stan do JSON
	jsonData, err := json.Marshal(state)
	if err != nil {
		return fmt.Errorf("nie można serializować stanu systemu: %v", err)
	}

	// Utwórz request
	req, err := http.NewRequest("POST", s.URL, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("nie można utworzyć żądania HTTP: %v", err)
	}

	// Ustaw nagłówki
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "SafetyTwin-Agent/1.0")

	// Wyślij request
	resp, err := s.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("błąd podczas wysyłania danych: %v", err)
	}
	defer resp.Body.Close()

	// Sprawdź kod odpowiedzi
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("serwer zwrócił błąd: %s", resp.Status)
	}

	return nil
}

// SaveStateToFile zapisuje stan systemu do pliku JSON
func SaveStateToFile(state *models.SystemState, stateDir string) error {
	// Utwórz nazwę pliku na podstawie aktualnego czasu
	timestamp := time.Now().Format("20060102-150405")
	filename := fmt.Sprintf("%s/state-%s.json", stateDir, timestamp)

	// Serializuj stan do JSON
	jsonData, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("nie można serializować stanu systemu: %v", err)
	}

	// Zapisz do pliku
	if err := os.WriteFile(filename, jsonData, 0644); err != nil {
		return fmt.Errorf("nie można zapisać pliku stanu: %v", err)
	}

	return nil
}
