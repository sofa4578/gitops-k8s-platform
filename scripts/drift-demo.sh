#!/usr/bin/env bash
#
# drift-demo.sh — the platform's signature demonstration: manually scale a
# Deployment out-of-band (simulating someone running `kubectl scale` by
# hand instead of going through Git) and watch Argo CD's selfHeal revert it
# within one reconciliation cycle.
#
# Targets team-alpha's PROD release. tenants/team-alpha/applications.yaml
# deploys BOTH a dev and a prod Application into the same team-alpha
# namespace, so the Deployment is not literally named "webapp" (as
# blueprint section 7 Phase 12's pseudocode assumes) — Helm's fullname
# template prefixes it with the Argo CD Application/Helm release name,
# giving "team-alpha-prod-webapp". prod is the target here (not dev)
# because its hostname, alpha.platform.local, is the one already wired up
# in /etc/hosts per docs/bootstrap.md.
#
# Requires: kubectl pointed at the bootstrapped cluster. Does not create,
# delete, or apply anything — it only scales an existing Deployment and
# then reads its state back.
set -euo pipefail

readonly NAMESPACE="team-alpha"
readonly DEPLOYMENT="team-alpha-prod-webapp"
readonly SCALE_TO=7
readonly POLL_INTERVAL_SECONDS=10
readonly MAX_ATTEMPTS=24 # 24 * 10s = 4 minutes — Argo CD polls Git every 3m by default

current=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT" -o jsonpath='{.spec.replicas}')
echo "Current replicas: ${current}"

echo "Manually scaling to ${SCALE_TO} (simulating an out-of-band change)..."
kubectl -n "$NAMESPACE" scale deploy "$DEPLOYMENT" --replicas="$SCALE_TO"

echo "Waiting for Argo CD to reconcile (selfHeal: true in every Application's syncPolicy)..."
for i in $(seq 1 "$MAX_ATTEMPTS"); do
  replicas=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT" -o jsonpath='{.spec.replicas}')
  echo "  t+$((i * POLL_INTERVAL_SECONDS))s: replicas=${replicas}"
  if [[ "$replicas" != "$SCALE_TO" ]]; then
    echo "Reverted by Argo CD. Self-heal confirmed."
    # TODO(sofiia): note the actual elapsed time here (t+Ns above) and carry
    # it into README.md's "measured recovery time" TODO — this script prints
    # it, it does not need to be re-measured separately.
    exit 0
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done

echo "Not reverted after $((MAX_ATTEMPTS * POLL_INTERVAL_SECONDS))s — check the Application's syncPolicy.automated.selfHeal setting." >&2
exit 1
