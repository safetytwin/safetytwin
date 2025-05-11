package utils

import (
	"safetytwin/agent/models"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestNewSender(t *testing.T) {
	// Test tworzenia Sendera z domyślnymi opcjami
	bridgeURL := "http://example.com/api"
	sender := NewSender(bridgeURL)

	if sender.bridgeURL != bridgeURL {
		t.Errorf("Niepoprawny URL: got %v, want %v", sender.bridgeURL, bridgeURL)
	}
	if sender.maxRetries != 3 {
		t.Errorf("Niepoprawna liczba ponownych prób: got %v, want %v", sender.maxRetries, 3)
	}
	if sender.retryBackoff != time.Second {
		t.Errorf("Niepoprawny backoff: got %v, want %v", sender.retryBackoff, time.Second)
	}

	// Test tworzenia Sendera z niestandardowymi opcjami
	customTimeout := 5 * time.Second
	customRetries := 5
	customBackoff := 2 * time.Second

	sender = NewSender(
		bridgeURL,
		WithTimeout(customTimeout),
		WithRetries(customRetries, customBackoff),
	)

	if sender.client.Timeout != customTimeout {
		t.Errorf("Niepoprawny timeout: got %v, want %v", sender.client.Timeout, customTimeout)
	}
	if sender.maxRetries != customRetries {
		t.Errorf("Niepoprawna liczba ponownych prób: got %v, want %v", sender.maxRetries, customRetries)
	}
	if sender.retryBackoff != customBackoff {
		t.Errorf("Niepoprawny backoff: got %v, want %v", sender.retryBackoff, customBackoff)
	}
}

func TestSendState(t *testing.T) {
	// Utwórz testowy serwer HTTP
	var receivedData []byte
	var requestCount int

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++

		// Sprawdź metodę HTTP
		if r.Method != "POST" {
			t.Errorf("Niepoprawna metoda HTTP: got %v, want POST", r.Method)
		}

		// Sprawdź nagłówki
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("Niepoprawny Content-Type: got %v, want application/json", r.Header.Get("Content-Type"))
		}
		if r.Header.Get("User-Agent") != "safetytwin-Agent/1.0" {
			t.Errorf("Niepoprawny User-Agent: got %v, want safetytwin-Agent/1.0", r.Header.Get("User-Agent"))
		}

		// Odczytaj dane
		decoder := json.NewDecoder(r.Body)
		var data map[string]interface{}
		if err := decoder.Decode(&data); err != nil {
			t.Errorf("Błąd dekodowania JSON: %v", err)
		}

		// Zapisz dane
		receivedData, _ = json.Marshal(data)

		// Odpowiedz z sukcesem
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	// Utwórz Sender z testowym serwerem
	sender := NewSender(
		server.URL,
		WithRetries(1, 100*time.Millisecond), // Małe wartości dla szybszego testu
	)

	// Utwórz testowy stan
	state := &models.SystemState{
		Hostname: "test-host",
		Timestamp: time.Now().Unix(),
	}

	// Wyślij stan
	err := sender.SendState(state)
	if err != nil {
		t.Fatalf("Błąd wysyłania stanu: %v", err)
	}

	// Sprawdź, czy serwer otrzymał dane
	if requestCount != 1 {
		t.Errorf("Niepoprawna liczba żądań: got %v, want 1", requestCount)
	}

	// Sprawdź, czy dane są poprawne
	var receivedState map[string]interface{}
	if err := json.Unmarshal(receivedData, &receivedState); err != nil {
		t.Fatalf("Błąd dekodowania otrzymanych danych: %v", err)
	}

	if receivedState["hostname"] != "test-host" {
		t.Errorf("Niepoprawna nazwa hosta: got %v, want test-host", receivedState["hostname"])
	}
}

func TestSendStateWithRetries(t *testing.T) {
	// Utwórz testowy serwer HTTP, który najpierw zwraca błąd, a potem sukces
	var requestCount int
	maxFailures := 2

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++

		if requestCount <= maxFailures {
			// Pierwsze żądania zakończone niepowodzeniem
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		// Kolejne żądania zakończone sukcesem
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	// Utwórz Sender z testowym serwerem i krótkimi czasami ponownych prób
	sender := NewSender(
		server.URL,
		WithRetries(3, 100*time.Millisecond),
	)

	// Wyślij stan
	state := &models.SystemState{
		Hostname: "test-host",
		Timestamp: time.Now().Unix(),
	}

	err := sender.SendState(state)
	if err != nil {
		t.Fatalf("Błąd wysyłania stanu po ponownych próbach: %v", err)
	}

	// Sprawdź, czy liczba żądań jest zgodna z oczekiwaniami
	expectedRequests := maxFailures + 1 // Nieudane próby + jedna udana
	if requestCount != expectedRequests {
		t.Errorf("Niepoprawna liczba żądań: got %v, want %v", requestCount, expectedRequests)
	}
}

func TestSendStateWithMaxRetriesExceeded(t *testing.T) {
	// Utwórz testowy serwer HTTP, który zawsze zwraca błąd
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	// Utwórz Sender z testowym serwerem i krótkimi czasami ponownych prób
	sender := NewSender(
		server.URL,
		WithRetries(2, 100*time.Millisecond),
	)

	// Wyślij stan
	state := &models.SystemState{
		Hostname: "test-host",
		Timestamp: time.Now().Unix(),
	}

	// Powinien wystąpić błąd po wyczerpaniu liczby ponownych prób
	err := sender.SendState(state)
	if err == nil {
		t.Fatal("Oczekiwano błędu po wyczerpaniu liczby ponownych prób, ale nie wystąpił")
	}
}
