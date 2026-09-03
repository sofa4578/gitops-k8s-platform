# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0]

### Added
- Full CI: `ci-manifests.yml` (yamllint, helm lint, helm unittest, a
  4-way env x tenant `kubeconform -strict` + `trivy config` matrix),
  `ci-app.yml` (ruff, pytest, docker build, `trivy image` scan gated
  on CRITICAL, push to GHCR), `promote.yml` (automated dev promotion
  PRs), `security.yml` (scheduled gitleaks + trivy fs). Dependabot and
  CODEOWNERS.
- `platform/cert-manager/issuers/`: a self-signed CA chain for local
  TLS, and an optional Let's Encrypt DNS-01 issuer for a public demo.
- Operational scripts: `bootstrap.sh` (idempotent, empty cluster to
  fully synced platform), `verify.sh` (asserts the platform's actual
  guarantees), `drift-demo.sh` (self-heal demonstration), `teardown.sh`.
- Full documentation set: four ADRs, `docs/architecture.md`,
  `docs/bootstrap.md`, `docs/promotion.md`, `docs/troubleshooting.md`
  (all 8 runbook scenarios), and this README.

## [0.2.0]

### Added
- `charts/webapp`: a hand-written Helm chart with `values.schema.json`
  validation (rejects `image.tag: latest`), HPA, PodDisruptionBudget,
  NetworkPolicy, and 9 helm-unittest tests.
- `tenants/team-alpha` and `tenants/team-beta`: namespace-level
  isolation via RBAC, default-deny NetworkPolicy (explicit DNS and
  ingress-nginx allows only), ResourceQuota, LimitRange, and a
  per-tenant Argo CD `AppProject`.
- `envs/dev` and `envs/prod` values overlays — 1 replica / no
  autoscaling in dev, 3 replicas / HPA / PodDisruptionBudget in prod.
- `scripts/seal-secret.sh` and `docs/security.md` — the sanctioned
  path for committing an encrypted tenant secret, and the threat
  model behind it.

### Fixed
- `bootstrap/root-app.yaml` changed from a single `path: platform`
  source to a multi-source Application (`platform/` + `tenants/`,
  both recursive) — a single source never reconciled `tenants/` at
  all, which the sync-wave design requires (see ADR notes in
  `docs/architecture.md`).

## [0.1.0]

### Added
- Repository skeleton, `.gitignore`, `Makefile`, `.yamllint.yaml`,
  `.gitleaks.toml`, PR template, MIT license.
- `src/webapp`: a minimal FastAPI service (`/`, `/health`, `/ready`,
  `/metrics`, optional chaos endpoints) with unit tests.
- `src/webapp/Dockerfile`: multi-stage, non-root (uid 10001), a venv
  at `/opt/venv`, base image pinned by digest.
- `kind/cluster.yaml`: a three-node local cluster with ingress port
  mappings.
- `bootstrap/argocd`: Argo CD installed via Kustomize at a pinned
  version, with a small `argocd-cm` patch.
- `bootstrap/root-app.yaml` and `platform/*/application.yaml`:
  app-of-apps bootstrapping ingress-nginx, cert-manager,
  sealed-secrets, metrics-server, and a minimal monitoring stack, with
  sync waves ordering CRD-dependent components correctly.
