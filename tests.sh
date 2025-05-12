#!/bin/bash
# tests.sh - Run full infrastructure and web tests after system startup

cd "$(dirname "$0")"

# 1. Run Ansible infrastructure tests
if [ -f ansible/inventory.ini ] && [ -f ansible/test_infra.yml ]; then
  echo "[INFO] Running Ansible infrastructure tests..."
  ansible-playbook -i ansible/inventory.ini ansible/test_infra.yml || {
    echo "[ERROR] Ansible infrastructure tests failed!"; exit 1;
  }
else
  echo "[WARN] Ansible files missing, skipping infra tests."
fi

# 2. Check orchestrator web endpoints
function check_endpoint() {
  url="$1"
  desc="$2"
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  if [ "$code" = "200" ]; then
    echo "[PASS] $desc ($url)"
  else
    echo "[FAIL] $desc ($url) - HTTP $code"
  fi
}

check_endpoint "http://localhost:8000/vm_grid" "Dashboard VM Grid"
check_endpoint "http://localhost:8000/vms" "API: VM List"

# 3. Test shell endpoints for all VMs in inventory
if [ -f ansible/inventory.ini ]; then
  grep -oE '^[^# ]+' ansible/inventory.ini | grep -v '\[' | while read vm; do
    if [ -n "$vm" ]; then
      check_endpoint "http://localhost:8000/shell/$vm" "Shell endpoint for $vm"
    fi
  done
fi

echo "[INFO] All tests completed."
