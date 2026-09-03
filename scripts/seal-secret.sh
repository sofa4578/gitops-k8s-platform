#!/usr/bin/env bash
#
# seal-secret.sh — the one sanctioned path for adding a tenant secret to
# this repository. It never writes plaintext to disk: it pipes a
# --dry-run=client Secret manifest straight into kubeseal and prints (or
# redirects) the resulting SealedSecret, which is safe to commit to Git.
#
# Prerequisites:
#   - kubectl, pointed at the target cluster (read access is enough; this
#     script never applies anything, it only asks the API server to render
#     a Secret it will never create).
#   - kubeseal 0.27.1, matching the sealed-secrets controller version this
#     platform deploys (see platform/sealed-secrets/application.yaml).
#     Install it from the *bitnami* org (the project moved from
#     bitnami-labs to bitnami; bitnami-labs.github.io/sealed-secrets now
#     404s):
#
#       KUBESEAL_VERSION=0.27.1
#       ARCH=amd64   # or arm64
#       curl -sLo kubeseal.tar.gz \
#         "https://github.com/bitnami/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz"
#       tar xzf kubeseal.tar.gz kubeseal
#       sudo install kubeseal /usr/local/bin/
#
#   - A reachable cluster with the sealed-secrets controller running in
#     kube-system: kubeseal fetches the controller's *public* key over the
#     Kubernetes API to encrypt with, so this script cannot run offline and
#     cannot run against a cluster that hasn't bootstrapped platform/
#     sealed-secrets yet.
#
# This script only ever prints a SealedSecret to stdout. It does not run
# kubectl apply and does not touch the cluster's actual state.
set -euo pipefail

readonly CONTROLLER_NAMESPACE="kube-system"

usage() {
  cat <<'EOF'
Usage: seal-secret.sh <namespace> <secret-name> KEY=VALUE [KEY=VALUE ...]

Seal one or more literal key=value pairs into a SealedSecret manifest,
printed on stdout. Redirect it into the tenant's directory to commit it.

Arguments:
  <namespace>    Namespace the Secret (and SealedSecret) will live in.
                 A SealedSecret is bound to this namespace + name pair at
                 encryption time — it cannot be copied to another
                 namespace and still decrypt.
  <secret-name>  Name of the Secret to create.
  KEY=VALUE      One or more literal entries, e.g. API_KEY=changeme.
                 At least one is required.

Options:
  -h, --help     Show this help message and exit.

Example:
  scripts/seal-secret.sh team-alpha app-secrets \
    API_KEY=replace-me DB_PASSWORD=replace-me \
    > tenants/team-alpha/sealed-secret.yaml

Requires: kubectl (cluster access) and kubeseal 0.27.1 on PATH.
See the comment block at the top of this file for install instructions.
EOF
}

die() {
  echo "seal-secret.sh: error: $*" >&2
  exit 1
}

# A DNS-1123 label: lowercase alphanumeric and '-', not starting or ending
# with '-'. Both Kubernetes namespaces and Secret names must satisfy this,
# so validating here fails fast with a clear message instead of letting
# kubectl reject it deeper in the pipeline.
is_dns1123_label() {
  [[ "$1" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

if [[ $# -lt 3 ]]; then
  die "expected <namespace> <secret-name> and at least one KEY=VALUE pair (got $#)."
fi

namespace="$1"
secret_name="$2"
shift 2

is_dns1123_label "$namespace" \
  || die "'$namespace' is not a valid namespace name (lowercase alphanumeric and '-')."
is_dns1123_label "$secret_name" \
  || die "'$secret_name' is not a valid Secret name (lowercase alphanumeric and '-')."

# Everything left on the command line must be a KEY=VALUE literal.
# Validated up front, before anything touches the cluster, so a typo fails
# with a precise message instead of a confusing kubectl/kubeseal error.
literal_args=()
for pair in "$@"; do
  key="${pair%%=*}"
  if [[ "$key" == "$pair" ]]; then
    die "'$pair' is not in KEY=VALUE form."
  fi
  if [[ -z "$key" ]]; then
    die "'$pair' has an empty key."
  fi
  if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    die "'$key' is not a valid env-style key (letters, digits, underscore; cannot start with a digit)."
  fi
  literal_args+=("--from-literal=${pair}")
done

command -v kubectl >/dev/null 2>&1 \
  || die "kubectl not found on PATH. It's required to render the (never-created) plaintext Secret."
command -v kubeseal >/dev/null 2>&1 \
  || die "kubeseal not found on PATH. Install v0.27.1 — see the comment block at the top of this script."

# --dry-run=client: kubectl only renders YAML locally, it never sends this
# plaintext Secret to the API server. kubeseal is the only step that talks
# to the cluster, and only to fetch the controller's public key.
kubectl create secret generic "$secret_name" \
  --namespace "$namespace" \
  "${literal_args[@]}" \
  --dry-run=client \
  -o yaml \
| kubeseal \
  --format yaml \
  --controller-namespace "$CONTROLLER_NAMESPACE"
