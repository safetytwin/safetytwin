package utils

import (
	"bytes"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNewLogger(t *testing.T) {
	// Utwórz tymczasowy katalog na pliki testowe
	tempDir := t.TempDir()
	logFile := filepath.Join(tempDir, "test.log")

	// Test tworzenia loggera
	logger, err := NewLogger(logFile, LogLevelInfo, false)
	if err != nil {
		t.Fatalf("Nie można utworzyć loggera: %v", err)
	}
	defer logger.Close()

	// Sprawdź, czy plik został utworzony
	if _, err := os.Stat(logFile); os.IsNotExist(err) {
		t.Errorf("Plik dziennika nie został utworzony")
	}

	// Sprawdź, czy logger ma poprawny poziom
	if logger.level != LogLevelInfo {
		t.Errorf("Niepoprawny poziom logowania: got %v, want %v", logger.level, LogLevelInfo)
	}
}

func TestLoggerLevels(t *testing.T) {
	// Utwórz bufor na wyjście loggera
	var buf bytes.Buffer

	// Utwórz logger z buforem jako wyjściem
	errorLogger := NewCustomLogger(&buf, "ERROR: ")
	warningLogger := NewCustomLogger(&buf, "WARNING: ")
	infoLogger := NewCustomLogger(&buf, "INFO: ")
	debugLogger := NewCustomLogger(&buf, "DEBUG: ")

	logger := &Logger{
		errorLogger:   errorLogger,
		warningLogger: warningLogger,
		infoLogger:    infoLogger,
		debugLogger:   debugLogger,
		level:         LogLevelInfo,
	}

	// Test logowania na różnych poziomach
	logger.Error("Test error")
	logger.Warning("Test warning")
	logger.Info("Test info")
	logger.Debug("Test debug")

	// Sprawdź, czy wiadomości zostały zalogowane poprawnie
	output := buf.String()
	if !strings.Contains(output, "ERROR: Test error") {
		t.Errorf("Brak wiadomości błędu w wyjściu")
	}
	if !strings.Contains(output, "WARNING: Test warning") {
		t.Errorf("Brak wiadomości ostrzeżenia w wyjściu")
	}
	if !strings.Contains(output, "INFO: Test info") {
		t.Errorf("Brak wiadomości informacyjnej w wyjściu")
	}
	if strings.Contains(output, "DEBUG: Test debug") {
		t.Errorf("Wiadomość debugowania nie powinna być zalogowana na poziomie INFO")
	}

	// Zmień poziom logowania i sprawdź ponownie
	buf.Reset()
	logger.SetLevel(LogLevelDebug)
	logger.Debug("Test debug again")

	output = buf.String()
	if !strings.Contains(output, "DEBUG: Test debug again") {
		t.Errorf("Brak wiadomości debugowania w wyjściu po zmianie poziomu")
	}
}

func TestMultiWriter(t *testing.T) {
	// Utwórz bufory na wyjście
	var buf1, buf2 bytes.Buffer

	// Utwórz MultiWriter
	mw := NewMultiWriter(&buf1, &buf2)

	// Zapisz dane
	testData := []byte("Test MultiWriter")
	n, err := mw.Write(testData)
	if err != nil {
		t.Fatalf("Błąd zapisu: %v", err)
	}
	if n != len(testData) {
		t.Errorf("Niepoprawna liczba zapisanych bajtów: got %v, want %v", n, len(testData))
	}

	// Sprawdź, czy dane zostały zapisane do obu buforów
	if buf1.String() != string(testData) {
		t.Errorf("Niepoprawne dane w buforze 1: got %v, want %v", buf1.String(), string(testData))
	}
	if buf2.String() != string(testData) {
		t.Errorf("Niepoprawne dane w buforze 2: got %v, want %v", buf2.String(), string(testData))
	}

	// Test z błędem zapisu
	errorWriter := &errorWriter{err: io.ErrShortWrite}
	mw = NewMultiWriter(errorWriter)
	_, err = mw.Write(testData)
	if err != io.ErrShortWrite {
		t.Errorf("Oczekiwano błędu ErrShortWrite, otrzymano: %v", err)
	}
}

// Pomocnicza struktura do testowania błędów zapisu
type errorWriter struct {
	err error
}

func (w *errorWriter) Write(p []byte) (n int, err error) {
	return 0, w.err
}

// NewCustomLogger tworzy logger z niestandardowym wyjściem (tylko do testów)
func NewCustomLogger(w io.Writer, prefix string) *log.Logger {
	return log.New(w, prefix, 0)
}
