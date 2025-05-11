import os
from string import Template

TEMPLATE_PATH = os.path.join(os.path.dirname(__file__), '../templates/service.template')
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '../services')

SERVICES = [
    {
        'filename': 'agent_send_state.service',
        'DESCRIPTION': 'SafetyTwin Agent State Sender',
        'TYPE': 'simple',
        'USER': os.getenv('USER', 'tom'),
        'WORKDIR': os.getenv('SAFETYTWIN_HOME', '/home/tom/gitlab/safetytwin/safetytwin'),
        'EXECSTART': '/bin/bash ${WORKDIR}/agent_send_state.sh',
        'RESTART': 'on-failure',
    },
    {
        'filename': 'orchestrator.service',
        'DESCRIPTION': 'SafetyTwin Orchestrator (FastAPI)',
        'TYPE': 'simple',
        'USER': os.getenv('USER', 'tom'),
        'WORKDIR': os.getenv('SAFETYTWIN_HOME', '/home/tom/gitlab/safetytwin/safetytwin'),
        'EXECSTART': '/usr/bin/env uvicorn orchestrator:app --host 0.0.0.0 --port 8000',
        'RESTART': 'on-failure',
    },
    {
        'filename': 'snapshot-backup.service',
        'DESCRIPTION': 'SafetyTwin VM Snapshot Backup',
        'TYPE': 'oneshot',
        'USER': os.getenv('USER', 'tom'),
        'WORKDIR': os.getenv('SAFETYTWIN_HOME', '/home/tom/gitlab/safetytwin/safetytwin'),
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

def main():
    for svc in SERVICES:
        content = render_service(svc)
        outpath = os.path.join(OUTPUT_DIR, svc['filename'])
        with open(outpath, 'w') as f:
            f.write(content)
        print(f"Generated: {outpath}")

if __name__ == '__main__':
    main()
