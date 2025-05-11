#!/usr/bin/env python3
"""
Skrypt uruchamiający API VM Bridge.
"""

import sys
import os

# Dodaj katalog nadrzędny do ścieżki, aby umożliwić importowanie modułów
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

# Importuj i uruchom główną funkcję z modułu api
from api.run import main

if __name__ == '__main__':
    main()
