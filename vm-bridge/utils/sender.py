import json
import logging
import requests

class Sender:
    """
    Odpowiada za wysyłanie danych do VM Bridge (POST JSON na wskazany endpoint).
    """
    def __init__(self, bridge_url, timeout=30):
        self.bridge_url = bridge_url
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'safetytwin-Agent/1.0'
        })
        self.timeout = timeout

    def send_state(self, state):
        """
        Wysyła stan systemu do VM Bridge jako JSON przez HTTP POST.
        Zwraca True jeśli sukces, False w przeciwnym razie.
        """
        try:
            data = json.dumps(state)
            resp = self.session.post(self.bridge_url, data=data, timeout=self.timeout)
            if 200 <= resp.status_code < 300:
                logging.info(f"Stan wysłany do {self.bridge_url} (kod {resp.status_code})")
                return True
            else:
                logging.error(f"Błąd odpowiedzi z bridge: {resp.status_code} {resp.text}")
                return False
        except Exception as e:
            logging.error(f"Błąd wysyłania stanu do bridge: {e}")
            return False
