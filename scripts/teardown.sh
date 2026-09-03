#!/usr/bin/env bash
#
# teardown.sh — delete the local kind cluster entirely. Everything the
# platform manages is reconstructed from Git by scripts/bootstrap.sh; the
# one thing that is NOT reconstructed automatically is the sealed-secrets
# controller's private key, generated fresh by a new cluster. Any
# SealedSecret already committed to this repo was encrypted for the OLD
# key and becomes permanently undecryptable the moment this script runs,
# unless that key was backed up first (see docs/security.md's backup
# procedure).
set -euo pipefail

readonly CLUSTER_NAME="${CLUSTER_NAME:-gitops-platform}"

if kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key &>/dev/null \
   && [[ -n "$(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o name 2>/dev/null)" ]]; then
  cat >&2 <<'EOF'
WARNING: the sealed-secrets controller's private key is about to be
destroyed with this cluster. If you have committed any SealedSecret to
this repo and have NOT already backed up the key, do so now in another
terminal before continuing:

  kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
    -o yaml > sealed-secrets-key-backup.yaml

Store that file somewhere outside this repo and outside the cluster (see
docs/security.md) — it is never safe to commit.

EOF
  read -r -p "Continue tearing down '${CLUSTER_NAME}'? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted." >&2; exit 1 ;;
  esac
fi

kind delete cluster --name "$CLUSTER_NAME"
