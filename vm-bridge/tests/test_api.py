import pytest
from flask import Flask
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from main import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_status(client):
    resp = client.get('/api/v1/status')
    assert resp.status_code == 200
    data = resp.get_json()
    assert 'status' in data
    assert data['status'] in ['running', 'error']

def test_snapshots(client):
    resp = client.get('/api/v1/snapshots')
    assert resp.status_code == 200
    data = resp.get_json()
    assert 'snapshots' in data or 'current' in data

def test_update_state(client):
    # Minimal valid state payload
    payload = {
        "timestamp": "2025-05-11T10:00:00Z",
        "hardware": {"hostname": "test"},
        "services": [],
        "processes": []
    }
    resp = client.post('/api/v1/update_state', json=payload)
    assert resp.status_code in (200, 201)
    data = resp.get_json()
    assert 'status' in data
