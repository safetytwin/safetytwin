#!/bin/bash
# Zbiera listę usług i procesów i wysyła do Orchestratora
ORCH_URL="http://127.0.0.1:8000/api/state"
SERVICES=$(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}' | jq -R . | jq -s .)
PROCESSES=$(ps aux | jq -R . | jq -s .)
DATA="{\"services\": $SERVICES, \"processes\": $PROCESSES}"
curl -X POST -H "Content-Type: application/json" -d "$DATA" "$ORCH_URL"
