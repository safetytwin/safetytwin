package utils

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sync"
)

// LogLevel określa poziom logowania
type LogLevel int

const (
	// LogLevelError to poziom logowania tylko błędów
	LogLevelError LogLevel = iota
	// LogLevelWarning to poziom logowania ostrzeżeń i błędów
	LogLevelWarning
	// LogLevelInfo to poziom logowania informacji, ostrzeżeń i błędów
	LogLevelInfo
	// LogLevelDebug to poziom logowania debugowania, informacji, ostrzeżeń i błędów
	LogLevelDebug
)

// Logger to własny logger z poziomami logowania
type Logger struct {
	errorLogger   *log.Logger
	warningLogger *log.Logger
	infoLogger    *log.Logger
	debugLogger   *log.Logger
	level         LogLevel
	mu            sync.Mutex
	file          *os.File
}

// NewLogger tworzy nowy logger
func NewLogger(logFile string, level LogLevel, verbose bool) (*Logger, error) {
	// Utwórz katalog dla pliku dziennika, jeśli nie istnieje
	logDir := filepath.Dir(logFile)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return nil, fmt.Errorf("nie można utworzyć katalogu dla pliku dziennika %s: %w", logDir, err)
	}

	// Otwórz plik dziennika
	file, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return nil, fmt.Errorf("nie można otworzyć pliku dziennika %s: %w", logFile, err)
	}

	var output io.Writer
	if verbose {
		// W trybie verbose loguj zarówno do pliku, jak i na standardowe wyjście
		output = NewMultiWriter(file, os.Stdout)
	} else {
		// W trybie normalnym loguj tylko do pliku
		output = file
	}

	// Utwórz loggery dla różnych poziomów
	errorLogger := log.New(output, "ERROR: ", log.Ldate|log.Ltime|log.Lmicroseconds|log.Lshortfile)
	warningLogger := log.New(output, "WARNING: ", log.Ldate|log.Ltime|log.Lmicroseconds|log.Lshortfile)
	infoLogger := log.New(output, "INFO: ", log.Ldate|log.Ltime|log.Lmicroseconds|log.Lshortfile)
	debugLogger := log.New(output, "DEBUG: ", log.Ldate|log.Ltime|log.Lmicroseconds|log.Lshortfile)

	return &Logger{
		errorLogger:   errorLogger,
		warningLogger: warningLogger,
		infoLogger:    infoLogger,
		debugLogger:   debugLogger,
		level:         level,
		file:          file,
	}, nil
}

// Close zamyka plik dziennika
func (l *Logger) Close() error {
	if l.file != nil {
		return l.file.Close()
	}
	return nil
}

// SetLevel ustawia poziom logowania
func (l *Logger) SetLevel(level LogLevel) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.level = level
}

// Error loguje błąd
func (l *Logger) Error(format string, v ...interface{}) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.errorLogger.Output(2, fmt.Sprintf(format, v...))
}

// Warning loguje ostrzeżenie
func (l *Logger) Warning(format string, v ...interface{}) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.level >= LogLevelWarning {
		l.warningLogger.Output(2, fmt.Sprintf(format, v...))
	}
}

// Info loguje informację
func (l *Logger) Info(format string, v ...interface{}) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.level >= LogLevelInfo {
		l.infoLogger.Output(2, fmt.Sprintf(format, v...))
	}
}

// Debug loguje informację debugowania
func (l *Logger) Debug(format string, v ...interface{}) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.level >= LogLevelDebug {
		l.debugLogger.Output(2, fmt.Sprintf(format, v...))
	}
}

// ConfigureLogger konfiguruje globalny logger (dla kompatybilności)
func ConfigureLogger(logFile string, verbose bool) error {
	// Utwórz katalog dla pliku dziennika, jeśli nie istnieje
	logDir := filepath.Dir(logFile)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return fmt.Errorf("nie można utworzyć katalogu dla pliku dziennika %s: %w", logDir, err)
	}

	// Otwórz plik dziennika
	file, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("nie można otworzyć pliku dziennika %s: %w", logFile, err)
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
	writers []io.Writer
	mu      sync.Mutex
}

// NewMultiWriter tworzy nowy MultiWriter
func NewMultiWriter(writers ...io.Writer) *MultiWriter {
	w := make([]io.Writer, 0, len(writers))
	for _, writer := range writers {
		if writer != nil {
			w = append(w, writer)
		}
	}
	return &MultiWriter{writers: w}
}

// Write implementuje io.Writer
func (mw *MultiWriter) Write(p []byte) (n int, err error) {
	mw.mu.Lock()
	defer mw.mu.Unlock()
	
	for _, w := range mw.writers {
		n, err = w.Write(p)
		if err != nil {
			return
		}
		if n != len(p) {
			err = io.ErrShortWrite
			return
		}
	}
	return len(p), nil
}

// ErrShortWrite jest zwracany, gdy writer nie zapisał wszystkich danych
var ErrShortWrite = io.ErrShortWrite
