#!/usr/bin/env bash
#
# Asserts the platform's guarantees actually hold. Non-zero exit on any failure.
# Run it after bootstrap.sh, or any time you've poked the cluster by hand.
#
# Needs kubectl + jq.

# no -e: every check should run even if an earlier one fails
set -uo pipefail

FAILURES=0

pass() { echo "  PASS  $1"; }
fail() {
  echo "  FAIL  $1"
  FAILURES=$((FAILURES + 1))
}

echo "== Argo CD Applications: all Synced and Healthy =="
apps_json=$(kubectl -n argocd get applications -o json 2>&1) || {
  fail "could not list Applications in namespace argocd (is the cluster bootstrapped?)"
  apps_json=""
}
if [[ -n "$apps_json" ]]; then
  unhealthy=$(echo "$apps_json" | jq -r '
    .items[]
    | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
    | "\(.metadata.name): sync=\(.status.sync.status // "unknown") health=\(.status.health.status // "unknown")"
  ')
  total=$(echo "$apps_json" | jq '.items | length')
  if [[ -z "$unhealthy" && "$total" -gt 0 ]]; then
    pass "all ${total} Applications are Synced/Healthy"
  else
    fail "not all Applications are Synced/Healthy:"
    echo "$unhealthy" | sed 's/^/         /'
  fi
fi

echo "== Tenant webapp reachable over HTTPS =="
# -k: local issuer is self-signed
if curl -kfsS --max-time 5 https://alpha.platform.local/health >/dev/null 2>&1; then
  pass "https://alpha.platform.local/health returned 200"
else
  fail "https://alpha.platform.local/health did not respond — check ingress-nginx, DNS/hosts, and the Certificate's Ready status (docs/troubleshooting.md scenario 3 and 4)"
fi

echo "== Cross-tenant network isolation (team-alpha -> team-beta must time out) =="
# timeout == PASS here, it means default-deny is doing its job
if kubectl -n team-alpha run verify-isolation --rm -i --quiet --restart=Never \
    --image=curlimages/curl:8.10.1 --command --timeout=15s \
    -- curl -m 5 -s -o /dev/null http://team-beta-prod-webapp.team-beta.svc.cluster.local >/dev/null 2>&1; then
  fail "curl from team-alpha to team-beta SUCCEEDED — NetworkPolicy isolation is broken (docs/troubleshooting.md scenario 2)"
else
  pass "curl from team-alpha to team-beta timed out as expected — tenants are isolated"
fi

echo "== RBAC least privilege: webapp's own ServiceAccount can do nothing =="
can_i=$(kubectl auth can-i --list \
  --as="system:serviceaccount:team-alpha:team-alpha-prod-webapp" \
  -n team-alpha 2>&1) || true
# should be empty apart from the self-review verbs every identity gets
excess=$(echo "$can_i" | grep -vE '^\s*$|^Resources|selfsubjectaccessreviews|selfsubjectrulesreviews|^  \*\.\*' | grep -c '.*' || true)
if [[ "$excess" -le 3 ]]; then
  pass "system:serviceaccount:team-alpha:team-alpha-prod-webapp has no meaningful permissions"
else
  fail "system:serviceaccount:team-alpha:team-alpha-prod-webapp has more than the expected near-empty rule set:"
  echo "$can_i" | sed 's/^/         /'
fi

echo
echo "=================================================="
if [[ "$FAILURES" -eq 0 ]]; then
  echo "verify.sh: all checks PASSED"
  exit 0
else
  echo "verify.sh: ${FAILURES} check(s) FAILED"
  exit 1
fi
