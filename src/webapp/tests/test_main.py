"""Endpoint tests — the contract the probes and the chart depend on."""

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="module")
def client():
    # needs the "with" — that's what drives lifespan, otherwise /ready stays 503
    with TestClient(app) as test_client:
        yield test_client


def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200


def test_ready_returns_200_once_started(client):
    response = client.get("/ready")
    assert response.status_code == 200


def test_root_contains_expected_keys(client):
    response = client.get("/")
    assert response.status_code == 200
    body = response.json()
    assert body["app"] == "gitops-k8s-platform-webapp"
    assert body["version"]
    assert body["pod"] == "unknown"
    assert body["environment"] == "local"
