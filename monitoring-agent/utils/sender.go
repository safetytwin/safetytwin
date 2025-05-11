package utils

import (
	"bytes"
	"context"
	"safetytwin/agent/models"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Sender obsługuje wysyłanie danych do VM Bridge
type Sender struct {
	bridgeURL    string
	client       *http.Client
	maxRetries   int
	retryBackoff time.Duration
}

// SenderOption to opcja konfiguracji dla Sender
type SenderOption func(*Sender)

// WithTimeout ustawia timeout dla klienta HTTP
func WithTimeout(timeout time.Duration) SenderOption {
	return func(s *Sender) {
		s.client.Timeout = timeout
	}
}

// WithRetries ustawia parametry ponownych prób
func WithRetries(maxRetries int, backoff time.Duration) SenderOption {
	return func(s *Sender) {
		s.maxRetries = maxRetries
		s.retryBackoff = backoff
	}
}

// NewSender tworzy nowy obiekt Sender
func NewSender(bridgeURL string, options ...SenderOption) *Sender {
	s := &Sender{
		bridgeURL:    bridgeURL,
		client:       &http.Client{Timeout: 10 * time.Second},
		maxRetries:   3,
		retryBackoff: 1 * time.Second,
	}
	
	// Zastosuj opcje konfiguracji
	for _, option := range options {
		option(s)
	}
	
	return s
}

// SendState wysyła stan systemu do VM Bridge
func (s *Sender) SendState(state *models.SystemState) error {
	// Serializuj dane do JSON
	jsonData, err := json.Marshal(state)
	if err != nil {
		return fmt.Errorf("błąd serializacji danych: %w", err)
	}

	// Implementacja z ponownymi próbami
	var lastErr error
	for attempt := 0; attempt <= s.maxRetries; attempt++ {
		if attempt > 0 {
			// Czekaj przed ponowną próbą z wykładniczym backoff
			backoff := s.retryBackoff * time.Duration(1<<uint(attempt-1))
			time.Sleep(backoff)
		}
		
		// Utwórz kontekst z timeout
		ctx, cancel := context.WithTimeout(context.Background(), s.client.Timeout)
		defer cancel()
		
		// Przygotuj żądanie HTTP z kontekstem
		req, err := http.NewRequestWithContext(ctx, "POST", s.bridgeURL, bytes.NewBuffer(jsonData))
		if err != nil {
			lastErr = fmt.Errorf("błąd tworzenia żądania HTTP: %w", err)
			continue
		}

		// Ustaw nagłówki
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("User-Agent", "safetytwin-Agent/1.0")

		// Wyślij żądanie
		resp, err := s.client.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("błąd wysyłania żądania (próba %d/%d): %w", 
				attempt+1, s.maxRetries+1, err)
			continue
		}
		
		// Zamknij body odpowiedzi
		if resp.Body != nil {
			defer resp.Body.Close()
		}

		// Sprawdź kod odpowiedzi
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			lastErr = fmt.Errorf("nieoczekiwany kod odpowiedzi (próba %d/%d): %d", 
				attempt+1, s.maxRetries+1, resp.StatusCode)
			continue
		}
		
		// Sukces
		return nil
	}
	
	return fmt.Errorf("wyczerpano liczbę prób wysyłania stanu: %w", lastErr)
}
