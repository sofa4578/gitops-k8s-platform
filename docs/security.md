# Security

This document describes the threat model, the secrets-management design,
and the least-privilege controls that this platform relies on. It is the
canonical reference for "how does this system stay secure", and the
sealed-secrets private-key backup procedure at the end of this document is
the single most important recovery step in the whole platform — read that
section even if you skip everything else.

## 1. Threat model summary

### Trust boundaries

The system is built around one rule: **CI never touches the cluster.**
Every other boundary follows from that.

| Boundary | What crosses it | Why it's safe |
|---|---|---|
| Developer → GitHub | Git push, pull request | The only way to change cluster state. Direct `kubectl` access is read/diagnostic only. |
| GitHub → GitHub Actions | Workflow triggers | CI has no kubeconfig, no cluster token, no ServiceAccount. It validates and builds — nothing else. |
| GitHub Actions → GHCR | Built image | Authenticated with the ephemeral, workflow-scoped `GITHUB_TOKEN` (`packages: write`). No long-lived registry credential exists. |
| Argo CD → GitHub | Repository read | Public repo, read anonymously — no token to leak. |
| Argo CD → Kubernetes API | Manifest apply | Through an in-cluster ServiceAccount, scoped per tenant by an `AppProject` (`sourceRepos`, `destinations`, `namespaceResourceBlacklist`). |
| ingress-nginx → webapp Service | HTTP traffic | ClusterIP only, reachable only from pods the tenant's `NetworkPolicy` explicitly allows. |
| cert-manager → Let's Encrypt | ACME challenge | Only in the optional public-demo variant; the local kind cluster uses a self-signed `ClusterIssuer` and makes no external calls. |

### Security boundaries

1. **CI has no cluster access.** This is the load-bearing property of the
   whole design. A compromised GitHub Actions run (a malicious PR, a
   supply-chain-poisoned action) cannot reach the cluster, because there is
   nothing in CI's environment that lets it — no kubeconfig, no cluster
   token, no `kubectl apply` step anywhere in `.github/workflows/`.
2. **Every tenant is isolated on three independent layers**: RBAC (who can
   act), `NetworkPolicy` (who can talk to whom), `ResourceQuota` /
   `LimitRange` (how much any one tenant can consume). Losing one layer
   still leaves the other two standing.
3. **Secrets are encrypted at rest in Git.** The sealed-secrets private key
   never leaves the cluster; a copy of this repository, on its own, cannot
   be used to recover a single plaintext secret value.
4. **Pod Security Admission runs in `restricted` mode** on every tenant
   namespace (`pod-security.kubernetes.io/enforce: restricted`). Privileged
   containers, `hostNetwork`, `hostPath`, and running as root are rejected
   by the API server itself — not by a chart convention a values file could
   quietly override.

### What each control actually stops

| Control | Stops |
|---|---|
| No cluster credentials in CI | A compromised workflow run or malicious PR from reaching the Kubernetes API at all. |
| AppProject `sourceRepos` / `namespaceResourceBlacklist` | A tenant's own committed manifests from touching another tenant's namespace, or from creating a cluster-scoped resource. |
| Tenant `NetworkPolicy` (default-deny + explicit allows) | Lateral movement between tenant pods, and between a tenant and anything other than ingress-nginx and DNS. |
| Tenant `ResourceQuota` (`services.loadbalancers: "0"` included) | One tenant starving the cluster of CPU/memory, or provisioning an ungoverned second traffic entry point outside ingress-nginx. |
| Pod Security Admission `restricted` | A workload manifest, however it got committed, from running privileged or as root. |
| `readOnlyRootFilesystem` + `capabilities.drop: [ALL]` | A container-breakout attempt from persisting a change to its own image layer or using a Linux capability it has no legitimate need for. |
| SealedSecrets instead of plaintext | Anyone with read access to the Git repository (which is public) from ever seeing a secret value. |

## 2. Secrets management

Secrets are committed to Git as `SealedSecret` resources — the ciphertext
is safe to commit, GitHub is a public repository, and history can be
searched by anyone. The sealed-secrets controller in `kube-system` is the
only thing on Earth that holds the private key able to decrypt them.

### Sealed Secrets vs. SOPS + age + ksops vs. External Secrets Operator

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| SOPS + age + ksops | Flexible; works outside Kubernetes too (any file, not just Secrets) | Needs a custom ksops plugin baked into the Argo CD repo-server image, which complicates every Argo CD upgrade | Rejected for this build |
| External Secrets Operator | Secret values live in an external store (cloud secrets manager); rotation is centralized there | Requires an external provider — a paid or cloud-hosted secrets backend this project deliberately has none of | Rejected for local use; noted as a future extension |
| **Sealed Secrets** | Zero external dependencies; works with a vanilla Argo CD install; ciphertext is namespace+name bound | Private key is tied to one cluster and must be backed up by hand | **Chosen** |

Full rationale: `docs/decisions/002-secrets-management.md`.

### The one sanctioned path: `scripts/seal-secret.sh`

Nobody hand-runs `kubeseal` with ad-hoc flags, and nobody pastes a
plaintext `kubectl create secret ... | kubeseal` pipeline into a terminal
from memory — both are exactly how a stray plaintext Secret ends up
committed by accident. `scripts/seal-secret.sh` is the single, reviewed
wrapper for turning literal values into a committable `SealedSecret`:

```bash
scripts/seal-secret.sh team-alpha app-secrets \
  API_KEY=replace-me DB_PASSWORD=replace-me \
  > tenants/team-alpha/sealed-secret.yaml
```

It validates its arguments (namespace and secret name as DNS-1123 labels,
every value as `KEY=VALUE`), renders the Secret locally with
`kubectl create secret generic --dry-run=client -o yaml` (nothing is sent
to the API server at that step), and pipes that straight into
`kubeseal --format yaml --controller-namespace kube-system`. The plaintext
values exist only in the shell's argument list and in a pipe between two
local processes — never written to a temp file, never sent to the cluster
as a real Secret.

A `SealedSecret` is bound to the exact namespace + name pair it was
encrypted for, so it cannot be copied into another tenant's directory and
decrypted there — that binding is part of the ciphertext itself, not a
convention this repo has to enforce separately.

## 3. Least privilege / RBAC

Three independent identities are scoped down, each to the minimum it
needs:

- **The application's own ServiceAccount** (`charts/webapp/templates/serviceaccount.yaml`)
  carries no RBAC grants at all and sets
  `automountServiceAccountToken: false` — the webapp has no legitimate
  reason to call the Kubernetes API, so the token that would let it do so
  is never mounted into the pod in the first place, rather than relying on
  an empty Role alone to keep it powerless.
- **Argo CD's reach per tenant** is bounded by that tenant's `AppProject`
  (`tenants/*/appproject.yaml`): a fixed `sourceRepos` entry, a
  `destinations` list pinned to that tenant's own namespace, an empty
  `clusterResourceWhitelist`, and a `namespaceResourceBlacklist` that
  blocks even that tenant's own Application from touching its
  `ResourceQuota` or `LimitRange`. A compromised or careless commit under
  `tenants/team-alpha/` cannot sync a resource into `tenants/team-beta/`,
  or create a ClusterRole, however it's written.
- **The human tenant Role** (`tenants/*/rbac.yaml`) is a namespace-scoped
  `Role`, not a `ClusterRole`, granting read access to the workload and
  networking resources a team needs to diagnose its own deployment, plus
  `pods/exec` for a debug shell. `secrets` is deliberately excluded from
  the readable resource list — a broad `get`/`list` on Secrets would hand
  the whole team every decrypted `SealedSecret` value in the namespace.

Verification command (run against a live cluster; expected to be captured
manually, not asserted here):

```bash
kubectl auth can-i --list --as=system:serviceaccount:team-alpha:webapp -n team-alpha
```

TODO(sofiia): run the command above against the running kind cluster and
paste the actual output (or a screenshot of it) into the README's security
section — do not fabricate the output here.

## 4. Image scanning

`ci-app.yml` runs Trivy against the built image with
`--exit-code 1 --severity CRITICAL`: any CRITICAL finding fails the build
outright, before the image is ever pushed to GHCR. A separate weekly
scheduled scan re-checks the last published image, because new CVEs are
disclosed against already-built images all the time — a clean scan at
build time is not a permanent guarantee.

## 5. Manifest scanning

Two complementary checks, neither of which is sufficient alone:

- **`kubeconform -strict`** validates every rendered manifest against the
  upstream Kubernetes (and CRD) schemas — it catches typos, wrong types,
  and unknown fields, but has no opinion on whether a manifest is *safe*.
- **`trivy config`** against the rendered chart output catches the safety
  gaps schema validation can't see: a missing `runAsNonRoot`, a privileged
  container, a container with no resource limits set.

Both run in CI, against `helm template` output — never against a live
cluster, and neither ever gains cluster credentials to do so.

## 6. Branch protection

`main` is expected to require: a pull request before merge (no direct
pushes), passing status checks (lint, test, image scan, manifest scan),
linear history, and a block on force-push. `CODEOWNERS` requires review on
`charts/` and `platform/` specifically, since those are the paths that
change what actually runs in every tenant namespace.

## 7. CI/CD security summary

- CI never receives a kubeconfig, a cluster token, or a ServiceAccount —
  restated here because it is the property everything else in this
  document depends on.
- Every workflow in `.github/workflows/` declares an explicit, minimal
  `permissions:` block — `contents: read` by default, `packages: write`
  only in the job that pushes to GHCR.
- Every third-party GitHub Action is pinned by commit SHA, not by tag — a
  tag can be moved by whoever controls the upstream repo; a commit SHA
  cannot.
- `gitleaks` scans full history on every pull request, catching a
  plaintext secret before it lands on `main` rather than after.
- Dependabot (`.github/dependabot.yml`) watches `pip` dependencies in
  `src/webapp`, GitHub Actions versions, and the base Docker image, so a
  vulnerable pin doesn't sit unnoticed indefinitely.

## 8. Backups

This system is almost entirely stateless and reproducible from Git, with
exactly two things that are not:

1. **The sealed-secrets controller's private key.** This is the one piece
   of state in the entire platform that cannot be regenerated from Git —
   see the dedicated section below.
2. **The Git repository itself.** Every manifest, chart, and workflow is
   configuration-as-code; GitHub's own hosting (plus, ideally, a
   developer's local clones) is the backup for this half.

The application itself is explicitly *not* a backup concern: it is
stateless, holds no persistent volumes, and is fully reproducible by
resyncing from Git.

## 9. Sealed-secrets private key backup — read this before you need it

The sealed-secrets controller generates an asymmetric key pair on first
start and stores the private half in a `Secret` in `kube-system` named
`sealed-secrets-key<suffix>` (labeled
`sealedsecrets.bitnami.com/sealed-secrets-key`). Every `SealedSecret`
committed to this repository — for every tenant, forever — is ciphertext
that only that one private key can open.

**If that key is lost, it is not recoverable.** There is no "regenerate
and get the same key back." Destroying and recreating the cluster
(`make down && make up`) makes the controller generate a *brand-new* key
pair, and every `SealedSecret` already committed to Git becomes permanent,
unrecoverable ciphertext — the exact failure mode described in
`docs/BLUEPRINT.md`'s troubleshooting scenario 6. The only way to recover
is to re-run `scripts/seal-secret.sh` for every secret, from the original
plaintext values, against the new key — which only works if those
plaintext values were kept somewhere outside this repository in the first
place.

Backup command:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-key-backup.yaml
```

Rules for that file, without exception:

- It contains a plaintext private key. Treat it with the same care as a
  root credential, because functionally it is one — anyone holding it can
  decrypt every secret this platform has ever committed to Git.
- It must be stored **outside the cluster and outside this repository** —
  a backup that lives next to the thing it's meant to survive the loss of
  is not a backup.
- It must **never** be committed to Git, in this repo or any other, even
  in a "private" repository.

TODO(sofiia): decide where this backup actually lives — a password
manager entry or an offline encrypted vault, not specified further here —
and record that location somewhere durable outside this repo (not in
this document, since this document is public).

### Disaster recovery procedure

1. Create a new cluster: `make up`.
2. Restore the sealed-secrets private key from the backup above into the
   new cluster's `kube-system` namespace *before* the controller generates
   its own fresh key pair, so it picks up the restored one instead.
3. Bootstrap Argo CD: `make bootstrap`.
4. Apply the root Application (`bootstrap/root-app.yaml`) and wait for
   every platform and tenant Application to reach `Synced` / `Healthy`.
5. Verify: `scripts/verify.sh`.

TODO(sofiia): time this procedure end-to-end on the actual kind cluster
and record the measured wall-clock time as the RTO in the README — do not
estimate or fabricate this number here.
