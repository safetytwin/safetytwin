#!/bin/bash
# Zbiera listę usług i procesów i wysyła do Orchestratora
set -euo pipefail
ORCH_URL="http://127.0.0.1:8000/api/state"
SERVICES=$(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}' | jq -R . | jq -s .)
PROCESSES=$(ps aux | jq -R . | jq -s .)
DATA="{\"services\": $SERVICES, \"processes\": $PROCESSES}"
printf '%s' "$DATA" | curl --fail --silent --show-error --connect-timeout 5 --max-time 30 -X POST -H "Content-Type: application/json" --data-binary @- "$ORCH_URL"
