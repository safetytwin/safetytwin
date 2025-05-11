#!/bin/bash
# Skrypt do zatrzymywania i restartowania wszystkich usług związanych z projektem SafetyTwin
# Użycie: ./project_services_control.sh stop|restart

SERVICES=(
    agent_send_state
    orchestrator
    snapshot-backup
)

# Dodatkowe ścieżki do .service w katalogu services/
SERVICES_DIR="$(dirname "$0")/../services"

# Funkcja do zatrzymania usług
stop_services() {
    for svc in "${SERVICES[@]}"; do
        if systemctl list-units --full -all | grep -Fq "$svc.service"; then
            echo "Zatrzymuję usługę: $svc"
            sudo systemctl stop "$svc.service"
        elif [ -f "$SERVICES_DIR/$svc.service" ]; then
            echo "Zatrzymuję usługę (plik): $SERVICES_DIR/$svc.service"
            sudo systemctl stop "$SERVICES_DIR/$svc.service"
        fi
    done
}

# Funkcja do restartu usług
restart_services() {
    for svc in "${SERVICES[@]}"; do
        if systemctl list-units --full -all | grep -Fq "$svc.service"; then
            echo "Restartuję usługę: $svc"
            sudo systemctl restart "$svc.service"
        elif [ -f "$SERVICES_DIR/$svc.service" ]; then
            echo "Restartuję usługę (plik): $SERVICES_DIR/$svc.service"
            sudo systemctl restart "$SERVICES_DIR/$svc.service"
        fi
    done
}

if [ "$1" == "stop" ]; then
    stop_services
elif [ "$1" == "restart" ]; then
    restart_services
else
    echo "Użycie: $0 stop|restart"
    exit 1
fi
