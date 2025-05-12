#!/bin/bash
# SafetyTwin Dashboard Starter
# Uruchamia orchestrator, sprawdza zależności, otwiera dashboard i monitoruje jego status

set -e

cd "$(dirname "$0")"

# Sprawdź zależności
missing=""
for cmd in python3 uvicorn ansible virsh jq curl; do
  if ! command -v $cmd >/dev/null 2>&1; then
    missing+="$cmd "
  fi
done
if [ -n "$missing" ]; then
  echo "[ERROR] Brakujące zależności: $missing"
  echo "Uruchom najpierw: ./install.sh lub zainstaluj brakujące pakiety."
  exit 1
fi

# Automatyczna poprawa pliku usługi safetytwin-agent.service jeśli istnieje
AGENT_UNIT="/etc/systemd/system/safetytwin-agent.service"
AGENT_SH="$(pwd)/agent_send_state.sh"
if [ -f "$AGENT_UNIT" ] && [ -f "$AGENT_SH" ]; then
  if ! grep -q "$AGENT_SH" "$AGENT_UNIT"; then
    echo "[INFO] Aktualizuję ExecStart w $AGENT_UNIT na $AGENT_SH"
    sudo sed -i "s|^ExecStart=.*|ExecStart=$AGENT_SH|" "$AGENT_UNIT"
    sudo chmod +x "$AGENT_SH"
    sudo systemctl daemon-reload
    sudo systemctl restart safetytwin-agent.service
    echo "[INFO] safetytwin-agent.service zaktualizowany i zrestartowany."
  fi
fi

# Sprawdź i napraw usługi przed uruchomieniem dashboardu
services=(orchestrator.service safetytwin-agent.service agent_send_state.service)
all_ok=true
for svc in "${services[@]}"; do
  if systemctl list-unit-files | grep -q "$svc"; then
    status=$(systemctl is-active "$svc")
    if [ "$status" != "active" ]; then
      echo "[WARN] $svc nie działa (status: $status). Próba naprawy..."
      sudo systemctl restart "$svc"
      sleep 2
      status2=$(systemctl is-active "$svc")
      if [ "$status2" != "active" ]; then
        echo "[ERROR] $svc nadal nie działa. Sprawdź logi: journalctl -u $svc"
        all_ok=false
      else
        echo "[OK] $svc naprawiony."
      fi
    else
      echo "[OK] $svc działa."
    fi
  else
    echo "[INFO] Usługa $svc nie istnieje, pomijam."
  fi
done

if [ "$all_ok" != true ]; then
  echo "[FATAL] Nie wszystkie usługi działają poprawnie. Przerywam uruchamianie dashboardu."
  exit 2
fi

# Sprawdź, czy orchestrator już działa
if lsof -i:8000 | grep LISTEN >/dev/null; then
  echo "[INFO] Orchestrator już działa na porcie 8000."
else
  echo "[INFO] Uruchamiam orchestrator (FastAPI)..."
  nohup uvicorn orchestrator:app --host 0.0.0.0 --port 8000 > dashboard.log 2>&1 &
  sleep 2
fi

# Sprawdź, czy dashboard odpowiada
for i in {1..10}; do
  if curl -s http://127.0.0.1:8000/dashboard | grep -q SafetyTwin; then
    echo "[OK] Dashboard działa: http://127.0.0.1:8000/dashboard"
    exit 0
  fi
  sleep 1
done

echo "[ERROR] Dashboard nie odpowiada. Sprawdź dashboard.log lub status orchestratora."
exit 2
