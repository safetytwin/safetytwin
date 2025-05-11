#!/bin/bash
# Skrypt do monitorowania wolnego miejsca na partycji z VM snapshotami
# Możesz dodać do crona lub uruchamiać ręcznie

THRESHOLD=80  # procent użycia, przy którym generowany jest alert
PARTITION="/var/lib/vm-bridge"  # katalog, gdzie trzymasz snapshoty

USAGE=$(df -h "$PARTITION" | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$USAGE" -ge "$THRESHOLD" ]; then
  echo "[ALERT] Użycie dysku na $PARTITION przekroczyło $THRESHOLD% ($USAGE%)!"
  # Tu możesz dodać np. wysyłkę maila lub inny alert
else
  echo "[OK] Użycie dysku na $PARTITION: $USAGE%"
fi
