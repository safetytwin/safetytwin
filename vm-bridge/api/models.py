#!/usr/bin/env python3
"""
Modele danych dla API VM Bridge.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional, Any


@dataclass
class ServiceConfig:
    """Model konfiguracji usługi"""
    name: str
    config: Dict[str, Any]
    version: Optional[str] = None


@dataclass
class StateUpdate:
    """Model aktualizacji stanu"""
    services: List[ServiceConfig]
    timestamp: str
    source: str
    metadata: Optional[Dict[str, Any]] = None


@dataclass
class SnapshotInfo:
    """Model informacji o snapshocie"""
    name: str
    created: str
    services: List[str]
    description: Optional[str] = None


@dataclass
class ApiResponse:
    """Model odpowiedzi API"""
    status: str
    message: Optional[str] = None
    data: Optional[Dict[str, Any]] = None
