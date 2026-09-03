# ADR 001: Pull-based delivery via Argo CD, not `kubectl apply` in CI

## Context

Every change to this platform's desired state — a new tenant, a bumped
image tag, a tightened NetworkPolicy — has to reach a running Kubernetes
cluster somehow. There are exactly two shapes that transport can take:

- **Push**: a CI job holds cluster credentials and runs `kubectl apply` (or
  `helm upgrade`) directly against the API server as the last step of a
  pipeline.
- **Pull**: an agent running *inside* the cluster watches a Git repository
  and reconciles the cluster's live state to match it, on its own schedule,
  using credentials that never leave the cluster.

This decision shapes the entire security model of the repository, so it
was made first, before any platform component was chosen.

## Decision

Use Argo CD in pull mode. GitHub Actions (`.github/workflows/ci-*.yml`)
only validates manifests, builds and scans the application image, and
opens promotion pull requests — it never runs `kubectl apply`, never holds
a kubeconfig, and never authenticates to the cluster in any way. Argo CD,
running inside the cluster, polls this repository (anonymously — it's
public, so there is no token to leak) and applies whatever it finds,
self-healing any manual drift.

## Alternatives considered

- **`kubectl apply` in GitHub Actions after a successful build.** Simpler
  to reason about as a linear pipeline, and needs no in-cluster agent.
  Rejected: it requires storing a long-lived cluster credential as a GitHub
  secret, which turns "a malicious or compromised PR" into "a path to
  cluster compromise." It also cannot detect drift — a manual `kubectl
  edit` is invisible until the next deploy overwrites it, if ever.
- **Flux.** A directly comparable pull-based GitOps controller from the
  same CNCF-graduated tier as Argo CD. Rejected only for portfolio
  reasons: Argo CD ships a UI, which turns "the platform is healthy" into
  a screenshot instead of a paragraph, and it appears in more DevOps job
  postings in this market.

## Consequences

- CI's blast radius is capped at "can push an image to GHCR." It cannot
  touch the cluster, cannot read cluster secrets, cannot even see that the
  cluster exists.
- The cluster must have a way to reach GitHub (or GitHub must be able to
  webhook it) — an outbound-only dependency, never inbound.
- Rollback becomes a Git operation (`git revert`) rather than a pipeline
  re-run — see `docs/promotion.md` for the exact mechanics and the
  `kubectl rollout undo` vs. `selfHeal` trap this implies.
- Argo CD itself is the one component this repository cannot deploy via
  GitOps (it can't install itself before it exists) — hence `bootstrap/`
  being the one directory applied by hand, exactly once.
