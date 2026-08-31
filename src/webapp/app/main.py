"""Minimal FastAPI service for the gitops-k8s-platform webapp.

Endpoints:
  GET /        - app identity: name, version, pod name (downward API), environment
  GET /health  - liveness probe, always 200 while the process is alive
  GET /ready   - readiness probe, 503 until startup has finished
  GET /metrics - Prometheus text exposition format
  GET /crash   - (chaos, opt-in) kill the process to demo CrashLoopBackOff
  GET /load    - (chaos, opt-in) burn CPU to demo HPA scale-out
"""

import os
import time

from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_NAME = "gitops-k8s-platform-webapp"
APP_VERSION = "0.1.0"

# Read once at import time. In-cluster these come from the Deployment: POD_NAME
# via the Kubernetes downward API, APP_ENV as a plain env var per values overlay.
# The defaults let the app run and be tested with no cluster involved at all.
POD_NAME = os.environ.get("POD_NAME", "unknown")
APP_ENV = os.environ.get("APP_ENV", "local")

# Chaos endpoints must never exist in a prod-like environment by accident, so the
# flag is read once here and used below to decide whether to register the routes
# at all, not merely whether to answer them - an unset/false flag means the paths
# 404 exactly like any other undefined route.
ENABLE_CHAOS_ENDPOINTS = os.environ.get("ENABLE_CHAOS_ENDPOINTS", "false") == "true"

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests processed, by path and status code",
    ["path", "status_code"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds, by path",
    ["path"],
)

app = FastAPI(title=APP_NAME, version=APP_VERSION)

# Readiness is deliberately a separate signal from liveness: liveness answers
# "is the process alive", readiness answers "has startup finished and can this
# pod safely receive traffic behind a Service/Ingress". The flag starts false
# and is flipped exactly once, by the startup event handler below.
_ready = False


@app.on_event("startup")
async def _mark_ready() -> None:
    global _ready
    _ready = True


class PrometheusMiddleware:
    """Plain ASGI middleware, not Starlette's BaseHTTPMiddleware, so it observes
    the real status code written to the wire for every request - /metrics itself
    included - rather than a value re-derived from the route's return value."""

    def __init__(self, app):
        # Starlette's middleware stack instantiates every middleware as
        # cls(app=inner_app, **options), so the parameter must be named "app".
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        path = scope["path"]
        start = time.perf_counter()
        status_code = 500  # overwritten below unless the app never responds

        async def send_wrapper(message):
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            REQUEST_LATENCY.labels(path=path).observe(time.perf_counter() - start)
            REQUEST_COUNT.labels(path=path, status_code=status_code).inc()


app.add_middleware(PrometheusMiddleware)


@app.get("/")
async def read_root() -> dict:
    return {
        "app": APP_NAME,
        "version": APP_VERSION,
        "pod": POD_NAME,
        "environment": APP_ENV,
    }


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/ready")
async def ready() -> dict:
    if not _ready:
        raise HTTPException(status_code=503, detail="not ready")
    return {"status": "ready"}


@app.get("/metrics")
async def metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


if ENABLE_CHAOS_ENDPOINTS:
    # Registered inside this guard - not just answered differently inside a
    # handler - so that with the flag unset (the default everywhere except an
    # explicit HPA/CrashLoopBackOff demo) these paths do not exist at all.

    @app.get("/crash")
    async def crash() -> None:
        # os._exit skips cleanup and finally blocks on purpose: it reproduces a
        # hard process kill so the kubelet observes a genuine CrashLoopBackOff
        # instead of a graceful shutdown.
        os._exit(1)

    @app.get("/load")
    async def load() -> dict:
        # A busy-loop, not a sleep: this has to burn real CPU so an HPA with a
        # CPU-utilization target has something to react to.
        duration_seconds = 2.0
        deadline = time.perf_counter() + duration_seconds
        while time.perf_counter() < deadline:
            pass
        return {"status": "load-generated", "seconds": duration_seconds}
