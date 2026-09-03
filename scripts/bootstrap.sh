#!/usr/bin/env bash
#
# bootstrap.sh — from a running kind cluster (see `make up` / kind/cluster.yaml)
# to a fully synced platform. This is the ONLY thing applied by hand
# ("bootstrap/" per docs/architecture.md) — every subsequent change goes
# through Git, never through this script again for day-to-day work. Re-running
# it is safe: every step is either idempotent (`kubectl apply`) or checks
# current state before waiting, so running it twice in a row (per blueprint
# section 13's "make down && make up && bootstrap && verify" check) converges
# to the same result both times.
#
# Requires: kubectl and helm/kustomize (bundled with modern kubectl via
# `kubectl kustomize`), pointed at a cluster created by `make up`.
set -euo pipefail

echo "== Step 1/4: install Argo CD (bootstrap/argocd/, pinned v2.13.2) =="
kubectl apply -k bootstrap/argocd/

echo "== Step 2/4: wait for argocd-server =="
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "== Step 3/4: apply the root Application (app-of-apps) =="
# Idempotent: re-applying an unchanged Application is a no-op. root itself
# then recursively reconciles platform/ and tenants/ (see bootstrap/root-app.yaml's
# comment on why it needs both directory sources) — nothing after this point
# is ever applied directly again.
kubectl apply -f bootstrap/root-app.yaml

echo "== Step 4/4: wait for every Application to become Synced/Healthy =="
readonly POLL_INTERVAL_SECONDS=10
readonly MAX_ATTEMPTS=60 # 60 * 10s = 10 minutes

for i in $(seq 1 "$MAX_ATTEMPTS"); do
  apps_json=$(kubectl -n argocd get applications -o json 2>/dev/null || echo '{"items":[]}')
  total=$(echo "$apps_json" | jq '.items | length')
  ready=$(echo "$apps_json" | jq '[.items[] | select(.status.sync.status == "Synced" and .status.health.status == "Healthy")] | length')

  if [[ "$total" -gt 0 && "$ready" -eq "$total" ]]; then
    echo "All ${total} Applications are Synced/Healthy after $((i * POLL_INTERVAL_SECONDS))s."
    echo
    echo "Bootstrap complete. Next:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
    echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
    echo "  ./scripts/verify.sh"
    exit 0
  fi

  echo "  t+$((i * POLL_INTERVAL_SECONDS))s: ${ready}/${total} Applications Synced/Healthy"
  sleep "$POLL_INTERVAL_SECONDS"
done

echo "Timed out after $((MAX_ATTEMPTS * POLL_INTERVAL_SECONDS))s waiting for all Applications to become Synced/Healthy." >&2
echo "Check: kubectl -n argocd get applications" >&2
echo "See docs/troubleshooting.md, especially scenarios 1 (ComparisonError) and 5 (HPA vs Argo CD)." >&2
exit 1
