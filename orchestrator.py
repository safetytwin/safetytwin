from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
import json, subprocess, difflib, os
from datetime import datetime

app = FastAPI()
templates = Jinja2Templates(directory="templates")
STATE_FILE = '/tmp/last_state.json'
LOG_ORCH = '/var/log/syslog'  # lub /var/log/messages na CentOS
LOG_AGENT = '/var/log/syslog'

# --- Dashboard ---
@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    # Stan systemu
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            current_state = json.load(f)
    else:
        current_state = {"services": [], "processes": []}
    # Historia zmian (dummy: tylko 1 stan)
    history = [{"id": "current", "timestamp": datetime.now().isoformat(), "current": True}]
    # Logi orchestratora
    orchestrator_logs = tail_log(LOG_ORCH, "orchestrator")
    agent_logs = tail_log(LOG_AGENT, "agent")
    # Snapshoty VM
    snapshots = list_snapshots()
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "current_state": current_state,
        "history": history,
        "orchestrator_logs": orchestrator_logs,
        "agent_logs": agent_logs,
        "snapshots": snapshots
    })

def tail_log(path, keyword=None, lines=40):
    try:
        out = subprocess.check_output(["tail", "-n", str(lines), path], encoding="utf-8", errors="ignore")
        if keyword:
            return "\n".join([l for l in out.splitlines() if keyword in l or not keyword])
        return out
    except Exception:
        return "Brak logów lub brak uprawnień."

def list_snapshots():
    try:
        out = subprocess.check_output(["virsh", "snapshot-list", "digital-twin-vm", "--tree"], encoding="utf-8", errors="ignore")
        snaps = []
        for line in out.splitlines():
            if line.strip() and not line.startswith("Name") and not line.startswith("-"):
                parts = line.split()
                name = parts[0]
                created = " ".join(parts[1:]) if len(parts) > 1 else ""
                snaps.append({"name": name, "created": created})
        return snaps
    except Exception:
        return []

@app.post("/snapshots/create")
def create_snapshot():
    snap_name = f"manual-snap-{datetime.now().strftime('%Y%m%d%H%M%S')}"
    subprocess.run(["virsh", "snapshot-create-as", "digital-twin-vm", snap_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/snapshots/delete/{snap_name}")
def delete_snapshot(snap_name: str):
    subprocess.run(["virsh", "snapshot-delete", "digital-twin-vm", snap_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/snapshots/revert/{snap_name}")
def revert_snapshot(snap_name: str):
    subprocess.run(["virsh", "snapshot-revert", "digital-twin-vm", snap_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/sync")
def force_sync():
    # Wymuś synchronizację usług (ponownie wygeneruj services.yml i uruchom playbook)
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            data = json.load(f)
        new_services = set(data.get('services', []))
        with open('/tmp/services.yml', 'w') as f:
            f.write('services:\n')
            for svc in sorted(new_services):
                f.write(f'  - {svc}\n')
        subprocess.run(['ansible-playbook', '/opt/digital-twin/apply_services.yml'])
        snap_name = f"manual-sync-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        subprocess.run(['virsh', 'snapshot-create-as', 'digital-twin-vm', snap_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/rollback")
def rollback(snapshot_name: str = Form(...)):
    subprocess.run(["virsh", "snapshot-revert", "digital-twin-vm", snapshot_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/api/state")
async def receive_state(request: Request):
    data = await request.json()
    prev = json.load(open(STATE_FILE)) if os.path.exists(STATE_FILE) else {}
    json.dump(data, open(STATE_FILE, 'w'))
    # Diff services
    prev_services = set(prev.get('services', []))
    new_services = set(data.get('services', []))
    if new_services != prev_services:
        # Generate services.yml for Ansible
        with open('/tmp/services.yml', 'w') as f:
            f.write('services:\n')
            for svc in sorted(new_services):
                f.write(f'  - {svc}\n')
        # Call ansible-playbook
        subprocess.run(['ansible-playbook', '/opt/digital-twin/apply_services.yml'])
        # Create VM snapshot (example for KVM/libvirt)
        snap_name = f"auto-snap-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        subprocess.run(['virsh', 'snapshot-create-as', 'digital-twin-vm', snap_name])
    return {"status": "ok"}
