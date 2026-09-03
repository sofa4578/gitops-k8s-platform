# ADR 002: Sealed Secrets for secrets committed to Git

## Context

GitOps means the Git repository is the source of truth for cluster state —
but a plaintext credential can never be committed, so *some* secret needs
a mechanism to become a safely-committable Git object while still ending
up as a real Kubernetes `Secret` in the cluster. The chosen mechanism has
to work with a vanilla Argo CD install (no custom `repo-server` plugin) and
without an external paid service, since this platform runs at zero cost.

## Decision

Use Bitnami's **Sealed Secrets**. A cluster-side controller
(`platform/sealed-secrets/`, wave -1) holds an asymmetric keypair; anyone
with the public key (fetched live via `kubeseal`, see
`scripts/seal-secret.sh`) can encrypt a `Secret` into a `SealedSecret`
that is safe to commit — only the controller's private key, which never
leaves the cluster, can decrypt it back into a real `Secret`. The
encrypted payload is cryptographically bound to the target
namespace+name pair, so a `SealedSecret` copied into a different
namespace does not decrypt there either.

## Alternatives considered

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| SOPS + age + a `ksops` Argo CD plugin | Flexible; works outside Kubernetes too (CI, local files) | Requires a custom `repo-server` container/plugin — extra moving part on every Argo CD upgrade | Rejected for this MVP |
| External Secrets Operator | Secrets live in a real external store (Vault, cloud secret manager) with centralized rotation | Requires a paid or self-hosted external secret store — a dependency this zero-cost, single-cluster project doesn't otherwise need | Rejected here, noted as the natural next step for a real production deployment |
| Sealed Secrets | Zero external dependencies, works with a vanilla Argo CD, encryption is a local CLI step | Recovery of every committed secret depends entirely on one private key; that key has no built-in rotation/backup story | **Chosen** |

## Consequences

- `scripts/seal-secret.sh` is the *only* sanctioned way a secret enters
  this repository — see `docs/security.md` for the full procedure.
- The sealed-secrets controller's private key becomes the single most
  critical piece of state in the entire platform: losing it makes every
  already-committed `SealedSecret` permanently undecryptable, with no
  recovery path. `docs/security.md` documents the backup command; this is
  the first thing to actually do in a real deployment of this design,
  before any real secret is sealed.
- Re-creating the cluster from scratch (`scripts/teardown.sh` +
  `scripts/bootstrap.sh`) generates a *new* keypair unless the old private
  key is restored first — every previously-committed `SealedSecret`
  becomes unusable and must be re-sealed against the new public key.
- If this platform later needs centralized rotation, multi-cluster secret
  sharing, or an audit trail independent of Git, External Secrets
  Operator is the documented upgrade path, not a redesign.
