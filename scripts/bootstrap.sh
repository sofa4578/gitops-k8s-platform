#!/usr/bin/env bash
#
# Empty kind cluster -> fully synced platform. The only thing applied by hand;
# everything after this goes through git. Safe to re-run.
#
# Needs kubectl pointed at a cluster from `make up`.
set -euo pipefail

echo "== Step 1/4: install Argo CD (bootstrap/argocd/, pinned v2.13.2) =="
kubectl apply -k bootstrap/argocd/

echo "== Step 2/4: wait for argocd-server =="
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "== Step 3/4: apply the root Application (app-of-apps) =="
# root then reconciles platform/ and tenants/ on its own
kubectl apply -f bootstrap/root-app.yaml

echo "== Step 4/4: wait for every Application to become Synced/Healthy =="
readonly POLL_INTERVAL_SECONDS=10
readonly MAX_ATTEMPTS=60  # 10 min

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
