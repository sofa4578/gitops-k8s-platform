"""Tests for the webapp's core HTTP endpoints.

Only the contract the rest of the platform depends on is covered here: liveness
always answers, readiness reflects real startup state, and the root endpoint
carries the identity fields the chart/HPA demo relies on.
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="module")
def client():
    # TestClient only runs the app's startup handler when used as a context
    # manager (it drives the ASGI lifespan protocol on enter/exit), so the
    # readiness flag would never flip without this "with".
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
