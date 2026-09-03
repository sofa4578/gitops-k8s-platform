# pinned by digest so upstream rebuilds don't silently change the base
FROM python:3.12-slim@sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217 AS builder

WORKDIR /build

COPY requirements.txt .

# venv not --user: /root/.local isn't readable by uid 10001
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim@sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217

# uid 10001, no login shell — matches runAsUser in the chart
RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin appuser

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

# chown at copy time, useradd already ran above
COPY --chown=appuser:appuser app/ ./app/

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER 10001

EXPOSE 8000

# k8s probes handle this, HEALTHCHECK is ignored by kubelet
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
