"""Demo webapp for the platform.

/ identity, /health liveness, /ready readiness, /metrics prometheus,
/crash + /load chaos endpoints (opt-in).
"""

import os
import time

from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_NAME = "gitops-k8s-platform-webapp"
APP_VERSION = "0.1.0"

# set by the Deployment; defaults keep it runnable outside a cluster
POD_NAME = os.environ.get("POD_NAME", "unknown")
APP_ENV = os.environ.get("APP_ENV", "local")

# gates route registration below, so unset means the paths just 404
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

# separate from liveness: gates traffic, not restarts
_ready = False


@app.on_event("startup")
async def _mark_ready() -> None:
    global _ready
    _ready = True


class PrometheusMiddleware:
    """Plain ASGI, not BaseHTTPMiddleware — sees the real status code on the wire."""

    def __init__(self, app):
        # must be named "app", Starlette calls cls(app=inner_app)
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        path = scope["path"]
        start = time.perf_counter()
        status_code = 500  # overwritten unless the app never responds

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
    @app.get("/crash")
    async def crash() -> None:
        # os._exit, not sys.exit — want a hard kill, not a graceful shutdown
        os._exit(1)

    @app.get("/load")
    async def load() -> dict:
        # busy-loop not sleep, the HPA needs real CPU to react to
        duration_seconds = 2.0
        deadline = time.perf_counter() + duration_seconds
        while time.perf_counter() < deadline:
            pass
        return {"status": "load-generated", "seconds": duration_seconds}
