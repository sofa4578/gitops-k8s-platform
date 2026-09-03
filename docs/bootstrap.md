# Bootstrap: from an empty machine to a running platform

## Prerequisites

Install these, then confirm each with the version check shown:

| Tool | Version used to build this repo | Check |
|---|---|---|
| Docker | any recent version, kind requires it | `docker version` |
| kind | 0.25.0+ | `kind version` |
| kubectl | 1.37+ | `kubectl version --client` |
| helm | 3.21.4 | `helm version` |
| kubeseal | 0.27.1 (only needed to seal a secret, not to bootstrap) | `kubeseal --version` |
| yamllint | 1.38.0 (only needed to run `make lint` locally) | `yamllint --version` |

8 GB RAM minimum, 16 GB comfortable — Argo CD plus the platform
components use roughly 2.5-3 GB. If memory is tight, reduce
`kind/cluster.yaml` to one control-plane and one worker node and note
that in your own fork as an environment limitation.

## Step by step

```bash
git clone https://github.com/sofa4578/gitops-k8s-platform.git
cd gitops-k8s-platform

# 1. Local cluster
make up
kubectl get nodes
# Expect: 3 nodes, all Ready within about a minute.

# 2. Argo CD + the entire platform, one command
make bootstrap
# Runs scripts/bootstrap.sh: installs Argo CD (bootstrap/argocd/, pinned
# v2.13.2), waits for argocd-server, applies bootstrap/root-app.yaml, then
# polls until every Application is Synced/Healthy. Expect this to take
# 2-5 minutes on a first run — most of it is images pulling.

# 3. Open the Argo CD UI
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
# Visit https://localhost:8080, log in as "admin" with the password above.
# The certificate warning is expected -- Argo CD's own default cert is
# self-signed.

# 4. Point your hosts file at the cluster
# Linux/macOS: /etc/hosts   Windows: C:\Windows\System32\drivers\etc\hosts
#   127.0.0.1  argocd.platform.local alpha.platform.local beta.platform.local alpha-dev.platform.local beta-dev.platform.local

# 5. Verify
make verify
# Runs scripts/verify.sh: Argo CD Applications all Synced/Healthy, the
# webapp reachable over HTTPS, cross-tenant traffic timing out, and the
# app's own ServiceAccount holding no meaningful RBAC. Prints PASS/FAIL
# per check and exits non-zero on any failure.
```

Re-running `make bootstrap` is safe — every step is either an idempotent
`kubectl apply` or a poll against current state, so running the whole
sequence twice in a row converges to the same result both times.

## Expected output at each step

- `make up`: three `kind-gitops-platform-*` nodes reach `Ready` inside
  roughly a minute.
- `make bootstrap`, step "wait for argocd-server": a rollout status line
  ending in `deployment "argocd-server" successfully rolled out`.
- `make bootstrap`, final poll: a line like
  `All 10 Applications are Synced/Healthy after 140s.` (10 = `root`
  itself, 5 platform Applications — ingress-nginx, cert-manager,
  sealed-secrets, metrics-server, monitoring — and 4 tenant Applications —
  `team-alpha-dev`, `team-alpha-prod`, `team-beta-dev`, `team-beta-prod`.
  See `docs/architecture.md`'s component table.)
- `make verify`: one `PASS` line per check, ending in
  `verify.sh: all checks PASSED`.

## Most likely failure mode on a first run

**`kind create cluster` fails with "port is already allocated."**
Something else on your machine (a local nginx, Docker Desktop's own
proxy) already holds host port 80 or 443. Either free the port, or edit
`kind/cluster.yaml`'s `extraPortMappings` to use 8080/8443 and adjust
every `*.platform.local` URL in this document accordingly.

`charts/webapp`'s default Ingress annotation
(`cert-manager.io/cluster-issuer: selfsigned`) already matches this
repository's local ClusterIssuer
(`platform/cert-manager/issuers/selfsigned.yaml`), so a `Certificate`
issued out of the box against this repo as committed goes `Ready: True`
with no per-env override needed. To use real TLS with Let's Encrypt
instead, override the `cert-manager.io/cluster-issuer` annotation to
`letsencrypt-staging` or `letsencrypt-prod` in your env values file and
apply `platform/cert-manager/issuers/letsencrypt.yaml`.

See `docs/troubleshooting.md` for the full runbook if any of the above
doesn't resolve what you're seeing.
