#!/usr/bin/env bash
#
# Scale a Deployment out-of-band and watch Argo CD selfHeal put it back.
#
# Targets the prod release — deployment name is release-prefixed, dev and prod
# both live in team-alpha.
set -euo pipefail

readonly NAMESPACE="team-alpha"
readonly DEPLOYMENT="team-alpha-prod-webapp"
readonly SCALE_TO=7
readonly POLL_INTERVAL_SECONDS=10
readonly MAX_ATTEMPTS=24  # 4 min, Argo CD polls git every 3m

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
    # TODO(sofiia): copy the elapsed time above into README's recovery-time TODO
    exit 0
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done

echo "Not reverted after $((MAX_ATTEMPTS * POLL_INTERVAL_SECONDS))s — check the Application's syncPolicy.automated.selfHeal setting." >&2
exit 1
