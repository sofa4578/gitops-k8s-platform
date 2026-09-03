# ADR 004: Helm for `charts/webapp`, Kustomize for bootstrapping Argo CD

## Context

Kubernetes has two dominant templating/packaging tools, and this project
actually uses both — deliberately, in different places, rather than
picking one and forcing it everywhere. The question this ADR answers is
not "Helm or Kustomize" in the abstract, but which tool fits each of the
two jobs this repository needs done: (a) packaging a reusable, versioned,
parameterized application chart consumed by four different releases
(dev/prod × team-alpha/team-beta), and (b) installing a third party's
official manifest (Argo CD itself) with a couple of local patches, exactly
once, by hand.

## Decision

- **`charts/webapp`** is a hand-written Helm chart. It is the artifact
  this project most wants to demonstrate authorship of.
- **`bootstrap/argocd/`** uses Kustomize: a `kustomization.yaml` that
  layers a `namespace.yaml` and a small strategic-merge patch
  (`patches/argocd-cm.yaml`) on top of Argo CD's official, pinned
  `install.yaml`.

## Alternatives considered

- **Kustomize for `charts/webapp` too**, patching a base set of raw
  manifests per environment. Simpler mental model (no templating
  language), and would have been sufficient for four overlays. Rejected
  because it can't do what this ADR's decision needs to demonstrate:
  package versioning (`Chart.yaml`'s `version`/`appVersion` split),
  `values.schema.json` validation (the mechanism that rejects an
  `image.tag: latest` before a template even renders), and conditional
  template logic driven by a single flag (`autoscaling.enabled` controls
  both whether `hpa.yaml` renders at all *and* whether `deployment.yaml`
  omits `replicas` — expressing that with Kustomize patches means keeping
  two separate overlay trees in sync by hand).
- **Helm for bootstrapping Argo CD**, via `helm install` from the
  official chart. Rejected: `helm install` leaves a Helm *release* — state
  tracked in a Secret in the cluster — for a one-time, by-hand action that
  exists specifically because nothing else can bootstrap itself yet.
  Kustomize just renders YAML; there is no release object to manage, no
  `helm upgrade` drift to reconcile against Argo CD's own view of what it
  manages, and no chance of Helm's release state disagreeing with what
  `kubectl apply -k` actually put in the cluster.

## Consequences

- Two tools, two purposes, both narrower than "the general-purpose
  Kubernetes packaging tool" — Helm never touches `bootstrap/`, Kustomize
  never touches `charts/webapp`.
- `values.schema.json` is the one piece of this decision that would have
  been outright impossible with the rejected Kustomize-for-the-chart
  alternative, and it's the single strongest signal of Helm authorship
  skill in this repository — see `charts/webapp/tests/deployment_test.yaml`
  for the helm-unittest coverage proving it actually rejects `latest`.
- Every other `platform/*/application.yaml` also uses Helm (via Argo CD's
  native Helm source type) to consume third-party charts at a pinned
  `targetRevision` — this project never forks or vendors someone else's
  chart, it only declares which version and which values to install.
