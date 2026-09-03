# Architecture

## Components

| Component | Namespace | Role |
|---|---|---|
| kind | — | Local Kubernetes cluster (1 control-plane + 2 workers, see `kind/cluster.yaml`) |
| Argo CD | `argocd` | Reconciliation engine — manages itself (bootstrapped once, by hand) and everything else (via Git) |
| ingress-nginx | `ingress-nginx` | HTTP/HTTPS entrypoint, hostname-based routing |
| cert-manager | `cert-manager` | Issues and renews TLS certificates |
| sealed-secrets | `kube-system` | Decrypts a committed `SealedSecret` into a real `Secret`, in-cluster only |
| metrics-server | `kube-system` | CPU/memory metrics that the HPA reads |
| kube-prometheus-stack (minimal) | `monitoring` | Platform health only — not a full observability stack, see "Known limitations" in the README |
| webapp (team-alpha) | `team-alpha` | Two releases (dev + prod) of `charts/webapp` |
| webapp (team-beta) | `team-beta` | Same chart, isolated tenant |

## Two independent delivery flows

Manifests (platform components, tenant policy, chart values) and
application code (`src/webapp/`) are validated and delivered by two
separate pipelines, because they change at very different rates and carry
different risk:

```
Pull request touching charts/**, platform/**, tenants/**, envs/**
        |
        v
GitHub Actions: ci-manifests.yml
        |  yamllint -> helm lint -> helm unittest
        |  -> helm template | kubeconform -strict  (4-way env x tenant matrix)
        |  -> trivy config on rendered manifests
        v
Merge to main
        |
        v
Argo CD polls Git (default: every 3 minutes, or instantly via webhook)
        |
        v
application-controller compares desired (Git) vs. live (cluster)
        |
        v
Diff applied to the Kubernetes API, respecting sync-wave order
```

```
Push to src/webapp/**
        |
        v
GitHub Actions: ci-app.yml
        |  ruff -> pytest -> docker build -> trivy image scan (gate on CRITICAL) -> push to GHCR
        v
GitHub Actions: promote.yml
        |  opens a PR bumping image.tag in envs/dev/*.yaml
        v
Human review and merge -> Argo CD syncs dev
        |
        v
Manual PR copying the same tag into envs/prod/*.yaml -> Argo CD syncs prod
```

## Network flow

```
Browser
   | https://alpha.platform.local
   v
kind extraPortMappings (host :443 -> control-plane node :443)
   v
ingress-nginx Service (NodePort, hostPort enabled)
   v
ingress-nginx controller pod
   |  TLS termination via a cert-manager-issued Certificate
   |  routes on the Host header
   v
Service team-alpha-prod-webapp (ClusterIP) in namespace team-alpha
   v
Endpoints -> webapp pod
```

Every tenant namespace carries a default-deny `NetworkPolicy` plus two
explicit allows (see `tenants/*/networkpolicy.yaml`):
ingress only from `ingress-nginx`, egress only to `kube-system` DNS
(UDP **and** TCP 53). Traffic between `team-alpha` and `team-beta` is
never explicitly allowed, so it is implicitly denied — see
`docs/troubleshooting.md` scenario 2 for the failure mode this design
is guarding against.

## Connection-by-connection

- **Developer -> GitHub.** The only sanctioned way to change cluster
  state. Direct `kubectl` access exists for reading and diagnosing, never
  for applying.
- **GitHub -> GitHub Actions.** CI has no cluster access at all — no
  kubeconfig, no token, no ServiceAccount. It only validates and builds.
- **GitHub Actions -> GHCR.** Authenticated with the workflow-scoped
  `GITHUB_TOKEN` (`packages: write`), which expires with the job. No
  long-lived registry credential exists anywhere.
- **Argo CD -> GitHub.** Reads the repository. It's public, so this is
  anonymous — there is no token to leak.
- **Argo CD -> Kubernetes API.** Through an in-cluster ServiceAccount.
  Each tenant `Application` is scoped by an `AppProject`
  (`clusterResourceWhitelist: []`, `namespaceResourceBlacklist`), so even
  a bad commit under `tenants/team-alpha/` cannot create a cluster-scoped
  resource or touch that tenant's own `ResourceQuota`.
- **ingress-nginx -> webapp Service.** ClusterIP, reachable only because
  the tenant's `allow-from-ingress-nginx` NetworkPolicy explicitly permits
  it.
- **cert-manager -> Let's Encrypt.** Only in the optional public-demo
  path (`platform/cert-manager/issuers/letsencrypt.yaml`). The default
  local path uses a self-signed `ClusterIssuer` and makes no external
  calls at all.

## Security boundaries

1. **CI never touches the cluster.** The load-bearing property of the
   whole design — see ADR 001.
2. **Every tenant is isolated on three independent layers**: RBAC (who
   can act), `NetworkPolicy` (who can talk to whom), `ResourceQuota` /
   `LimitRange` (how much any one tenant can consume).
3. **Secrets are encrypted at rest in Git.** See ADR 002 and
   `docs/security.md`.
4. **Pod Security Admission in `restricted` mode** on both tenant
   namespaces forbids privileged containers, `hostNetwork`, `hostPath`,
   and running as root — independent of, and in addition to, the chart's
   own `securityContext` defaults.

## Bootstrap wave sequence

Order matters because several resources reference CRDs or capabilities
that only exist once an earlier wave has synced:

```
Wave -2:  tenant namespaces (team-alpha, team-beta — need their
          Pod Security Admission labels, so CreateNamespace=true alone
          isn't enough; every other namespace is created by its
          Application's syncOptions instead)
Wave -1:  sealed-secrets, cert-manager (installs its own CRDs)
Wave  0:  ingress-nginx, metrics-server
Wave  1:  cert-manager ClusterIssuers (need the CRDs from wave -1)
Wave  2:  tenant AppProject, RBAC, ResourceQuota, LimitRange, NetworkPolicy
Wave  3:  tenant webapp Applications (dev and prod)
```

`bootstrap/root-app.yaml` is a **multi-source** Application — this is a
deliberate deviation from the blueprint's original single-source example,
documented here because it fixes a real gap: a single `path: platform`
source (as the blueprint's Крок 6.1 literally shows) would never
reconcile `tenants/` at all, and wave 2/3 above are defined entirely
under `tenants/`. `root-app.yaml` instead declares two recursive
directory sources — `platform/` and `tenants/` — so both trees are
reconciled by the same root Application, in the same sync-wave order,
exactly as the table above describes. `charts/`, `envs/`, `scripts/`,
`docs/`, `kind/`, `bootstrap/`, `src/`, and `.github/` are deliberately
excluded from both sources: they hold Helm templates, values-only files,
or CI config, not raw manifests meant to be applied directly.
