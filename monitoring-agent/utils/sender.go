package utils

import (
	"bytes"
	"digital-twin/agent/models"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Sender obsługuje wysyłanie danych do VM Bridge
type Sender struct {
	bridgeURL string
	client    *http.Client
}

// NewSender tworzy nowy obiekt Sender
func NewSender(bridgeURL string) *Sender {
	return &Sender{
		bridgeURL: bridgeURL,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// SendState wysyła stan systemu do VM Bridge
func (s *Sender) SendState(state *models.SystemState) error {
	// Serializuj dane do JSON
	jsonData, err := json.Marshal(state)
	if err != nil {
		return fmt.Errorf("błąd serializacji danych: %v", err)
	}

	// Przygotuj żądanie HTTP
	req, err := http.NewRequest("POST", s.bridgeURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("błąd tworzenia żądania HTTP: %v", err)
	}

	// Ustaw nagłówki
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "Digital-Twin-Agent/1.0")

	// Wyślij żądanie
	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("błąd wysyłania żądania: %v", err)
	}
	defer resp.Body.Close()

	// Sprawdź kod odpowiedzi
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("nieoczekiwany kod odpowiedzi: %d", resp.StatusCode)
	}

	return nil
}
