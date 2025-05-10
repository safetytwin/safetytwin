package utils

import (
	"log"
	"os"
)

// ConfigureLogger konfiguruje logger
func ConfigureLogger(logFile string, verbose bool) error {
	// Utwórz katalog dla pliku dziennika, jeśli nie istnieje
	logDir := logFile[:len(logFile)-len("/digital-twin-agent.log")]
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return err
	}

	// Otwórz plik dziennika
	file, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}

	// Ustaw wyjście loggera
	if verbose {
		// W trybie verbose loguj zarówno do pliku, jak i na standardowe wyjście
		multiWriter := NewMultiWriter(file, os.Stdout)
		log.SetOutput(multiWriter)
	} else {
		// W trybie normalnym loguj tylko do pliku
		log.SetOutput(file)
	}

	// Ustaw format loggera
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)
	return nil
}

// MultiWriter implementuje io.Writer dla wielu writerów
type MultiWriter struct {
	writers []interface{ Write(p []byte) (n int, err error) }
}

// NewMultiWriter tworzy nowy MultiWriter
func NewMultiWriter(writers ...interface{ Write(p []byte) (n int, err error) }) *MultiWriter {
	return &MultiWriter{writers: writers}
}

// Write implementuje io.Writer
func (mw *MultiWriter) Write(p []byte) (n int, err error) {
	for _, w := range mw.writers {
		n, err = w.Write(p)
		if err != nil {
			return
		}
		if n != len(p) {
			err = ErrShortWrite
			return
		}
	}
	return len(p), nil
}

// ErrShortWrite jest zwracany, gdy writer nie zapisał wszystkich danych
var ErrShortWrite = os.ErrShortWrite
