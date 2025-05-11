from fastapi import FastAPI, Request, Form, status
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
import subprocess, os
from dotenv import load_dotenv
import json, subprocess, difflib, os
from datetime import datetime

app = FastAPI()
import os
TEMPLATES_DIR = os.path.join(os.path.dirname(__file__), "templates")
templates = Jinja2Templates(directory=TEMPLATES_DIR)
STATE_FILE = '/tmp/last_state.json'
LOG_ORCH = '/var/log/syslog'  # lub /var/log/messages na CentOS
LOG_AGENT = '/var/log/syslog'

@app.get("/shell/{vm_name}")
def shell_vm(vm_name: str):
    import os
    from dotenv import load_dotenv
    import logging
    import subprocess
    import socket
    # Szukaj .env w katalogu głównym projektu
    root_env = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '.env'))
    local_env = os.path.abspath(os.path.join(os.path.dirname(__file__), '.env'))
    env_found = False
    if os.path.exists(root_env):
        load_dotenv(dotenv_path=root_env)
        env_found = True
    elif os.path.exists(local_env):
        load_dotenv(dotenv_path=local_env)
        env_found = True
    else:
        logging.warning("Nie znaleziono pliku .env ani w katalogu głównym, ani lokalnie!")
    user = os.getenv('VM_USER')
    password = os.getenv('VM_PASS')
    # Sprawdź czy VM istnieje
    try:
        out = subprocess.check_output(['virsh', 'list', '--all'], encoding='utf-8', errors='ignore')
        if vm_name not in out:
            return JSONResponse({"error": f"VM '{vm_name}' nie istnieje (virsh list --all)."}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": f"Błąd sprawdzania VM: {e}"}, status_code=500)
    # Sprawdź czy port 8080 jest otwarty lokalnie (host)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(1)
    port_open = False
    try:
        sock.connect(('localhost', 8080))
        port_open = True
    except Exception:
        port_open = False
    finally:
        sock.close()
    if not port_open:
        return JSONResponse({"error": "Web terminal (gotty/shellinabox) nie działa na porcie 8080. Sprawdź usługę na VM."}, status_code=502)
    base_url = f"http://localhost:8080/?vm={vm_name}"
    if user and password:
        url = f"{base_url}&user={user}&pass={password}"
    else:
        url = base_url
        if not env_found:
            return JSONResponse({"error": "Brak pliku .env z danymi logowania do VM."}, status_code=500)
        elif not user or not password:
            return JSONResponse({"error": "Brak VM_USER lub VM_PASS w pliku .env!"}, status_code=500)
    return JSONResponse({"url": url})

# --- Dynamiczna lista VM ---
@app.get("/vms")
def list_vms():
    import subprocess
    vms = []
    try:
        out = subprocess.check_output(['virsh', 'list', '--all'], encoding='utf-8', errors='ignore')
        for line in out.splitlines()[2:]:
            parts = line.strip().split()
            if len(parts) >= 2:
                vm_name = parts[1]
                ip = None
                # Try to get the IP address using virsh domifaddr
                try:
                    ip_out = subprocess.check_output(['virsh', 'domifaddr', vm_name], encoding='utf-8', errors='ignore')
                    for ip_line in ip_out.splitlines()[2:]:
                        ip_parts = ip_line.strip().split()
                        # Usually the IP is in the 4th column (Address)
                        if len(ip_parts) >= 4 and ip_parts[3].count('.') == 3:
                            ip = ip_parts[3].split('/')[0]
                            break
                except Exception:
                    ip = None
                vms.append({'name': vm_name, 'ip': ip})
    except Exception as e:
        return {"vms": [], "error": str(e)}
    return {"vms": vms}

# --- Edycja opisu snapshotu ---
from fastapi import Form
@app.post("/snapshots/edit_desc/{snap_name}")
def edit_snapshot_desc(snap_name: str, desc: str = Form(...)):
    # Przykładowo: opis snapshotu zapisywany w pliku /var/lib/libvirt/snap_desc_{snap_name}.txt
    desc_dir = "/var/lib/libvirt/"
    fname = os.path.join(desc_dir, f"snap_desc_{snap_name}.txt")
    try:
        with open(fname, "w") as f:
            f.write(desc.strip())
        return {"success": True}
    except Exception as e:
        return {"success": False, "error": str(e)}

# --- Tworzenie nowej VM ---
from fastapi import BackgroundTasks
@app.post("/create_vm")
def create_vm():
    import subprocess, re
    import time
    # Znajdź wolną nazwę VM
    existing = set()
    for f in os.listdir('/var/lib/libvirt/images'):
        m = re.match(r'(safetytwin-vm|test-vm)(-(\d+))?\.qcow2', f)
        if m:
            base = m.group(1)
            num = int(m.group(3) or 0)
            existing.add(num)
    for n in range(1, 100):
        if n not in existing:
            vm_name = f'safetytwin-vm-{n}'
            break
    else:
        return {"success": False, "error": "Brak wolnych nazw VM"}
    try:
        # Uruchom preinstall.sh z nową nazwą VM
        proc = subprocess.run(["sudo", "bash", "preinstall.sh", vm_name], cwd=os.path.dirname(__file__), capture_output=True, text=True, timeout=600)
        if proc.returncode != 0:
            return {"success": False, "error": proc.stderr or proc.stdout}
        return {"success": True, "vm_name": vm_name}
    except Exception as e:
        return {"success": False, "error": str(e)}

# --- Dashboard ---
@app.get("/vm_grid", response_class=HTMLResponse)
def vm_grid(request: Request):
    # Pobierz listę VM
    vms = []
    try:
        out = subprocess.check_output(['virsh', 'list', '--all'], encoding='utf-8', errors='ignore')
        for line in out.splitlines()[2:]:
            parts = line.strip().split()
            if len(parts) >= 2:
                vms.append(parts[1])
        # Jeśli nie ma żadnych VM, utwórz domyślną
        if not vms:
            subprocess.run(['bash', 'scripts/create-vm.sh'], cwd=os.path.dirname(__file__), check=True)
            out = subprocess.check_output(['virsh', 'list', '--all'], encoding='utf-8', errors='ignore')
            for line in out.splitlines()[2:]:
                parts = line.strip().split()
                if len(parts) >= 2:
                    vms.append(parts[1])
    except Exception:
        pass
    # Pobierz snapshoty dla każdej VM (max 3 najnowsze)
    vm_snaps = {}
    for vm in vms:
        snaps = []
        try:
            out = subprocess.check_output(['virsh', 'snapshot-list', vm, '--tree'], encoding='utf-8', errors='ignore')
            for line in out.splitlines():
                if line.strip() and not line.startswith("Name") and not line.startswith("-"):
                    parts = line.split()
                    name = parts[0]
                    snaps.append(name)
        except Exception:
            pass
        vm_snaps[vm] = snaps[:3]
    return templates.TemplateResponse("vm_grid.html", {"request": request, "vms": vms, "vm_snaps": vm_snaps})

@app.post("/install_pkg/{vm_name}")
def install_pkg(vm_name: str, pkg: str = None):
    # Zainstaluj pakiet przez SSH na VM
    try:
        # Wczytaj dane logowania z .env
        env_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '.env'))
        load_dotenv(dotenv_path=env_path)
        user = os.getenv('VM_USER', 'ubuntu')
        password = os.getenv('VM_PASS', 'ubuntu')
        # Instalacja przez sshpass+ssh
        cmd = [
            'sshpass', '-p', password,
            'ssh', '-o', 'StrictHostKeyChecking=no', f'{user}@{vm_name}',
            f'sudo apt-get update && sudo apt-get install -y {pkg}'
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if proc.returncode == 0:
            return {"success": True}
        return {"success": False, "error": proc.stderr or proc.stdout}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/snapshots/revert/{vm_name}/{snap_name}")
def revert_snapshot_grid(vm_name: str, snap_name: str):
    try:
        proc = subprocess.run(["virsh", "snapshot-revert", vm_name, snap_name], capture_output=True, text=True, timeout=60)
        if proc.returncode == 0:
            return {"success": True}
        return {"success": False, "error": proc.stderr or proc.stdout}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    # Parametry sortowania/filtrowania snapshotów
    sort_by = request.query_params.get('sort', 'created')
    filter_text = request.query_params.get('filter', '').lower()
    # Stan systemu
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            current_state = json.load(f)
    else:
        current_state = {"services": [], "processes": []}
    # Historia zmian (lista plików state_*.json) – tylko unikalne stany
    import hashlib
    state_files = sorted([f for f in os.listdir('/tmp') if f.startswith('state_') and f.endswith('.json')], reverse=True)
    seen_hashes = set()
    unique_files = []
    for fname in state_files:
        fpath = os.path.join('/tmp', fname)
        with open(fpath, 'rb') as f:
            file_hash = hashlib.md5(f.read()).hexdigest()
        if file_hash not in seen_hashes:
            seen_hashes.add(file_hash)
            unique_files.append((fname, file_hash))
        else:
            try:
                os.remove(fpath)
            except Exception as e:
                print(f"Błąd usuwania {fpath}: {e}")
    history = []
    for fname, _ in unique_files:
        ts = fname.replace('state_','').replace('.json','')
        history.append({"id": fname, "timestamp": ts, "current": fname == os.path.basename(STATE_FILE)})
    # Logi orchestratora
    orchestrator_logs = tail_log(LOG_ORCH, "orchestrator")
    agent_logs = tail_log(LOG_AGENT, "agent")
    # Snapshoty VM (z opisami)
    snapshots = list_snapshots()
    # Dodaj opisy snapshotów jeśli istnieją
    for snap in snapshots:
        desc_path = f"/var/lib/libvirt/snap_desc_{snap['name']}.txt"
        if os.path.exists(desc_path):
            with open(desc_path) as f:
                snap['desc'] = f.read().strip()
        else:
            snap['desc'] = ''
    # Filtrowanie
    if filter_text:
        snapshots = [s for s in snapshots if filter_text in s['name'].lower() or filter_text in s.get('desc','').lower()]
    # Sortowanie
    if sort_by == 'name':
        snapshots.sort(key=lambda s: s['name'])
    elif sort_by == 'created':
        snapshots.sort(key=lambda s: s.get('created',''), reverse=True)
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "current_state": current_state,
        "history": history,
        "orchestrator_logs": orchestrator_logs,
        "agent_logs": agent_logs,
        "snapshots": snapshots
    })

@app.get("/history/{state_id}", response_class=HTMLResponse)
def history_detail(request: Request, state_id: str):
    state_path = f"/tmp/{state_id}"
    if not os.path.exists(state_path):
        return HTMLResponse("Stan nie istnieje.", status_code=404)
    with open(state_path) as f:
        state_data = json.load(f)
    # Diff z aktualnym stanem
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f2:
            current = json.load(f2)
        prev_services = set(state_data.get('services', []))
        curr_services = set(current.get('services', []))
        diff = list(sorted(curr_services - prev_services)) + list(sorted(prev_services - curr_services))
    else:
        diff = []
    return templates.TemplateResponse("history_detail.html", {
        "request": request,
        "state_id": state_id,
        "state_data": state_data,
        "diff": diff
    })

@app.post("/rollback_state/{state_id}")
def rollback_state(state_id: str):
    state_path = f"/tmp/{state_id}"
    if os.path.exists(state_path):
        import shutil
        shutil.copy(state_path, STATE_FILE)
    return RedirectResponse("/dashboard", status_code=303)

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
        out = subprocess.check_output(["virsh", "snapshot-list", "safetytwin-vm", "--tree"], encoding="utf-8", errors="ignore")
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
    subprocess.run(["virsh", "snapshot-create-as", "safetytwin-vm", snap_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/snapshots/delete/{snap_name}")
def delete_snapshot(snap_name: str):
    subprocess.run(["virsh", "snapshot-delete", "safetytwin-vm", snap_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/snapshots/revert/{snap_name}")
def revert_snapshot(snap_name: str):
    subprocess.run(["virsh", "snapshot-revert", "safetytwin-vm", snap_name])
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
        subprocess.run(['ansible-playbook', '/opt/safetytwin/apply_services.yml'])
        snap_name = f"manual-sync-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        subprocess.run(['virsh', 'snapshot-create-as', 'safetytwin-vm', snap_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/rollback")
def rollback(snapshot_name: str = Form(...)):
    subprocess.run(["virsh", "snapshot-revert", "safetytwin-vm", snapshot_name])
    return RedirectResponse("/dashboard", status_code=303)

@app.post("/api/state")
async def receive_state(request: Request):
    data = await request.json()
    import shutil
    from datetime import datetime
    if os.path.exists(STATE_FILE):
        ts = datetime.now().strftime('%Y%m%d%H%M%S')
        shutil.copy(STATE_FILE, f"/tmp/state_{ts}.json")
    json.dump(data, open(STATE_FILE, 'w'))
    prev = json.load(open(STATE_FILE)) if os.path.exists(STATE_FILE) else {}
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
        subprocess.run(['ansible-playbook', '/opt/safetytwin/apply_services.yml'])
        # Create VM snapshot (example for KVM/libvirt)
        snap_name = f"auto-snap-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        subprocess.run(['virsh', 'snapshot-create-as', 'safetytwin-vm', snap_name])
    return {"status": "ok"}
