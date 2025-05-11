"""
Service and Timer Generator for SafetyTwin
=========================================

This script generates systemd .service and .timer files from templates based on the SERVICES list below.

How to add a new service:
- Add a dictionary to the SERVICES list with the following keys:
    'filename', 'DESCRIPTION', 'TYPE', 'USER', 'WORKDIR', 'EXECSTART', 'RESTART'

How to add a timer for a service:
- Add a 'timer' key to the service dictionary with the following keys:
    'filename', 'DESCRIPTION', 'ON_BOOT_SEC', 'ON_ACTIVE_SEC', 'UNIT'
- Example:
    'timer': {
        'filename': 'my_service.timer',
        'DESCRIPTION': 'Periodic My Service',
        'ON_BOOT_SEC': '5min',
        'ON_ACTIVE_SEC': '5min',
        'UNIT': 'my_service.service',
    }

Run this script to (re)generate all service and timer files:
    python3 generate_services.py

Generated files are placed in ../services/.
"""
import os
from string import Template

TEMPLATE_PATH = os.path.join(os.path.dirname(__file__), '../templates/service.template')
TIMER_TEMPLATE_PATH = os.path.join(os.path.dirname(__file__), '../templates/timer.template')
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '../services')

SERVICES = [
    {
        'filename': 'agent_send_state.service',
        'DESCRIPTION': 'SafetyTwin Agent State Sender',
        'TYPE': 'oneshot',
        'USER': 'root',
        'WORKDIR': '$HOME/safetytwin/safetytwin',
        'EXECSTART': '/bin/bash ${WORKDIR}/agent_send_state.sh',
        'RESTART': 'no',
        'timer': {
            'filename': 'agent_send_state.timer',
            'DESCRIPTION': 'Periodic SafetyTwin Agent State Sender',
            'ON_BOOT_SEC': '10',
            'ON_ACTIVE_SEC': '10s',
            'UNIT': 'agent_send_state.service',
        },
    },
    {
        'filename': 'ssh_vm_check.service',
        'DESCRIPTION': 'Periodic SSH VM Connectivity Check',
        'TYPE': 'oneshot',
        'USER': 'root',
        'WORKDIR': '$HOME/safetytwin/safetytwin',
        'EXECSTART': '/bin/bash ${WORKDIR}/ssh_vm_check.sh',
        'RESTART': 'no',
        'timer': {
            'filename': 'ssh_vm_check.timer',
            'DESCRIPTION': 'Periodic SSH VM Connectivity Check',
            'ON_BOOT_SEC': '1min',
            'ON_ACTIVE_SEC': '5min',
            'UNIT': 'ssh_vm_check.service',
        },
    },
    {
        'filename': 'orchestrator.service',
        'DESCRIPTION': 'SafetyTwin Orchestrator (FastAPI)',
        'TYPE': 'simple',
        'USER': 'root',
        'WORKDIR': '$HOME/safetytwin/safetytwin',
        'EXECSTART': '/usr/bin/env uvicorn orchestrator:app --host 0.0.0.0 --port 8000',
        'RESTART': 'always',
    },
    {
        'filename': 'snapshot-backup.service',
        'DESCRIPTION': 'SafetyTwin VM Snapshot Backup',
        'TYPE': 'oneshot',
        'USER': 'root',
        'WORKDIR': '$HOME/safetytwin/safetytwin',
        'EXECSTART': '/bin/bash ${WORKDIR}/snapshot-backup.sh',
        'RESTART': 'no',
    },
]

def render_service(service: dict):
    with open(TEMPLATE_PATH) as f:
        template = Template(f.read())
    # Allow nested vars in EXECSTART
    svars = {k: v for k, v in service.items()}
    svars['EXECSTART'] = Template(svars['EXECSTART']).safe_substitute(svars)
    return template.safe_substitute(svars)

def render_timer(timer: dict):
    with open(TIMER_TEMPLATE_PATH) as f:
        template = Template(f.read())
    return template.safe_substitute(timer)

def main():
    for svc in SERVICES:
        # Generate .service file
        content = render_service(svc)
        outpath = os.path.join(OUTPUT_DIR, svc['filename'])
        with open(outpath, 'w') as f:
            f.write(content)
        print(f"Generated: {outpath}")
        # Generate .timer file if present
        if 'timer' in svc:
            timer_content = render_timer(svc['timer'])
            timer_outpath = os.path.join(OUTPUT_DIR, svc['timer']['filename'])
            with open(timer_outpath, 'w') as f:
                f.write(timer_content)
            print(f"Generated: {timer_outpath}")

if __name__ == '__main__':
    main()
