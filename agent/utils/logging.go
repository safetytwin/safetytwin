package utils

import (
	"io"
	"log"
	"os"
	"path/filepath"
)

// ConfigureLogger konfiguruje logger do zapisywania logów do pliku i na standardowe wyjście
func ConfigureLogger(logFile string, verbose bool) error {
	// Upewnij się, że katalog logów istnieje
	logDir := filepath.Dir(logFile)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return err
	}

	// Otwórz plik logów
	file, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return err
	}

	// Konfiguruj logger
	if verbose {
		// W trybie verbose zapisuj logi do pliku i na standardowe wyjście
		mw := io.MultiWriter(os.Stdout, file)
		log.SetOutput(mw)
	} else {
		// W trybie normalnym zapisuj logi tylko do pliku
		log.SetOutput(file)
	}

	// Ustaw format logów
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)

	return nil
}

// LogError zapisuje błąd do logów
func LogError(format string, v ...interface{}) {
	log.Printf("ERROR: "+format, v...)
}

// LogInfo zapisuje informację do logów
func LogInfo(format string, v ...interface{}) {
	log.Printf("INFO: "+format, v...)
}

// LogDebug zapisuje informację debugowania do logów (tylko w trybie verbose)
func LogDebug(verbose bool, format string, v ...interface{}) {
	if verbose {
		log.Printf("DEBUG: "+format, v...)
	}
}
