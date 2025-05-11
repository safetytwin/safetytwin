# !/usr/bin/env python3
# vm-bridge/utils/state_store.py
"""
Moduł do zarządzania stanem systemu.
"""

import os
import json
import time
import logging
import hashlib
from datetime import datetime
from deepdiff import DeepDiff

logger = logging.getLogger("vm-bridge.state_store")


class StateStore:
    """Klasa zarządzająca stanem systemu."""

    def __init__(self, state_dir):
        """Inicjalizacja store'a stanów."""
        self.state_dir = state_dir
        self.states = {}  # Przechowuje stany w pamięci (ID -> stan)
        self.current_state_id = None
        self.previous_state_id = None

        # Utwórz katalog stanów, jeśli nie istnieje
        os.makedirs(self.state_dir, exist_ok=True)

        # Wczytaj ostatni stan, jeśli istnieje
        self._load_latest_state()

    def _load_latest_state(self):
        """Wczytuje najnowszy stan z pliku."""
        latest_file = os.path.join(self.state_dir, "state_latest.json")

        if os.path.exists(latest_file):
            try:
                with open(latest_file, 'r') as f:
                    state_data = json.load(f)

                # Generuj ID dla stanu
                state_id = self._generate_state_id(state_data)

                # Zapisz stan w pamięci
                self.states[state_id] = state_data
                self.current_state_id = state_id

                logger.info(f"Wczytano ostatni stan systemu: {state_id}")
            except Exception as e:
                logger.error(f"Błąd podczas wczytywania ostatniego stanu: {e}")

    def _generate_state_id(self, state_data):
        """Generuje unikalne ID dla stanu systemu."""
        # Serializuj dane do JSON i oblicz hash
        state_json = json.dumps(state_data, sort_keys=True)
        return hashlib.md5(state_json.encode()).hexdigest()

    def save_state(self, state_data):
        """Zapisuje stan systemu."""
        try:
            # Generuj ID dla stanu
            state_id = self._generate_state_id(state_data)

            # Zapisz poprzednie ID
            if self.current_state_id:
                self.previous_state_id = self.current_state_id

            # Zapisz bieżące ID
            self.current_state_id = state_id

            # Zapisz stan w pamięci
            self.states[state_id] = state_data

            # Zapisz stan do pliku z timestampem
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            state_file = os.path.join(self.state_dir, f"state_{timestamp}.json")

            with open(state_file, 'w') as f:
                json.dump(state_data, f, indent=2)

            # Zapisz kopię jako 'latest'
            latest_file = os.path.join(self.state_dir, "state_latest.json")
            with open(latest_file, 'w') as f:
                json.dump(state_data, f, indent=2)

            # Usuwanie plików starszych niż 1h i trzymanie tylko 10 najnowszych
            self._cleanup_old_states(max_count=10, max_age_sec=3600)

            logger.info(f"Zapisano stan systemu: {state_id}")
            return state_id

        except Exception as e:
            logger.error(f"Błąd podczas zapisywania stanu: {e}")
            return None

    def _cleanup_old_states(self, max_count=10, max_age_sec=3600):
        """Usuwa pliki stanu starsze niż max_age_sec lub powyżej max_count najnowszych."""
        state_files = []
        now = time.time()
        for file in os.listdir(self.state_dir):
            if file.startswith("state_") and file.endswith(".json") and file != "state_latest.json":
                path = os.path.join(self.state_dir, file)
                mtime = os.path.getmtime(path)
                state_files.append((file, mtime, path))
        # Sortuj od najnowszych
        state_files.sort(key=lambda x: x[1], reverse=True)
        # Zostaw tylko max_count najnowszych
        keep = state_files[:max_count]
        to_delete = state_files[max_count:]
        # Usuń pliki starsze niż 1h lub przekraczające limit
        for file, mtime, path in to_delete:
            try:
                os.remove(path)
                logger.info(f"Usunięto stary plik stanu (limit): {file}")
            except Exception as e:
                logger.warning(f"Nie można usunąć pliku {file}: {e}")
        for file, mtime, path in keep:
            if now - mtime > max_age_sec:
                try:
                    os.remove(path)
                    logger.info(f"Usunięto stary plik stanu (wiek): {file}")
                except Exception as e:
                    logger.warning(f"Nie można usunąć pliku {file}: {e}")

    def get_state(self, state_id):
        """Pobiera stan o podanym ID."""
        return self.states.get(state_id)

    def compare_with_previous(self, state_id):
        """Porównuje stan z poprzednim stanem."""
        if not self.previous_state_id:
            logger.info("Brak poprzedniego stanu do porównania")
            return True, {"new_state": True}  # Zakładamy, że to nowy stan

        current_state = self.get_state(state_id)
        previous_state = self.get_state(self.previous_state_id)

        if not current_state or not previous_state:
            logger.error("Brak danych do porównania")
            return True, {"error": "Brak danych do porównania"}

        # Porównaj stany używając DeepDiff
        diff = DeepDiff(previous_state, current_state, ignore_order=True)

        # Sprawdź, czy są zmiany
        if diff:
            return True, diff
        else:
            return False, {}

    def get_state_history(self, limit=10):
        """Zwraca historię max 10 najnowszych stanów (starsze są usuwane)."""
        state_files = []

        # Znajdź pliki stanów w katalogu
        for file in os.listdir(self.state_dir):
            if file.startswith("state_") and file.endswith(".json") and file != "state_latest.json":
                file_path = os.path.join(self.state_dir, file)
                state_files.append((file, os.path.getmtime(file_path)))

        # Posortuj pliki według czasu modyfikacji (od najnowszych)
        state_files.sort(key=lambda x: x[1], reverse=True)

        # Ogranicz liczbę plików do 10 najnowszych
        state_files = state_files[:10]

        history = []
        for file, mtime in state_files:
            try:
                with open(os.path.join(self.state_dir, file), 'r') as f:
                    state_data = json.load(f)
                    state_id = self._generate_state_id(state_data)

                    history.append({
                        "id": state_id,
                        "file": file,
                        "timestamp": datetime.fromtimestamp(mtime).isoformat(),
                        "current": state_id == self.current_state_id
                    })
            except Exception as e:
                logger.error(f"Błąd podczas wczytywania pliku stanu {file}: {e}")

        return history