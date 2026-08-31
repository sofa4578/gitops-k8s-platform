# Base image pinned by digest, not tag: `python:3.12-slim` moves silently as
# upstream rebuilds it, which would make this build non-reproducible and let a
# new base image change under us without review. The tradeoff is a manual bump
# (see README) — in a real project Renovate or Dependabot opens that PR for you.
FROM python:3.12-slim@sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217 AS builder

WORKDIR /build

COPY requirements.txt .

# A venv at /opt/venv, never `pip install --user`: --user writes to
# /root/.local, which belongs to root and the non-root runtime user in the
# final stage cannot read — the exact failure this project is deliberately
# avoiding.
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim@sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217

# Fixed uid 10001, no login shell: Deployment securityContext (runAsNonRoot,
# runAsUser: 10001) must match this exactly or the container refuses to start.
RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin appuser

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

# --chown at copy time, after the user already exists: chown-ing afterwards
# with a separate RUN would need a root-owned intermediate layer and is easy
# to get wrong; copying straight to the final owner avoids that class of bug
# entirely (and the classic "Permission denied" from copying before useradd).
COPY --chown=appuser:appuser app/ ./app/

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER 10001

EXPOSE 8000

# No HEALTHCHECK: in Kubernetes a Docker-level healthcheck is never consulted
# by the kubelet — liveness/readiness probes on the Deployment are the real
# health signal, so one here would just be redundant, unused config.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
