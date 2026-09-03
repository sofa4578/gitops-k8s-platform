# Promotion: how a version moves from dev to prod

## The flow

```
Push to src/webapp/**
        |
        v
ci-app.yml: ruff -> pytest -> docker build -> trivy image scan -> push to GHCR
        |  tags: ghcr.io/sofa4578/webapp:<full 40-char SHA>
        |        ghcr.io/sofa4578/webapp:sha-<short 7-char SHA>
        v
promote.yml: opens a PR bumping image.tag in envs/dev/team-alpha.yaml
             and envs/dev/team-beta.yaml to that full SHA
        v
Human reviews and merges the PR
        v
Argo CD syncs team-alpha-dev / team-beta-dev to the new image
        v
Manual PR: copy the exact same image.tag value into
           envs/prod/team-alpha.yaml and envs/prod/team-beta.yaml
        v
Human reviews and merges
        v
Argo CD syncs team-alpha-prod / team-beta-prod
```

The step from dev to prod is intentionally manual (a hand-written PR, not
another automated one) — dev promotion happens on every successful build,
prod promotion happens on a human's decision that this specific,
already-running-in-dev build is ready.

## Why the full commit SHA, never `latest`

`latest` makes it impossible to know what's actually running from the tag
alone, and it breaks GitOps's core idempotency guarantee: Git wouldn't
change, but the image behind that tag could. The full SHA is unique,
immutable, and traces directly back to the exact commit and CI run that
produced it. `values.schema.json` enforces this at the chart level —
`image.tag: latest` fails schema validation before a template even
renders (see `charts/webapp/tests/deployment_test.yaml`'s first test).

## Concrete example

A promotion PR's entire diff is one line:

```diff
--- a/envs/dev/team-alpha.yaml
+++ b/envs/dev/team-alpha.yaml
@@ -6,7 +6,7 @@
 image:
   repository: ghcr.io/sofa4578/webapp
-  tag: "0.1.0"
+  tag: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
```

No rebuild happens between dev and prod. The artifact tested in dev and
the artifact running in prod are byte-for-byte the same image, referenced
by the same immutable digest-equivalent tag — only the deployment target
changes.

## Rollback: three mechanisms

1. **`git revert` (primary).** Revert the commit that bumped `image.tag`
   and push. Argo CD picks up the reverted state on its next
   reconciliation (poll interval, default ~3 minutes, or instantly via
   webhook) and syncs the previous image back. This is the mechanism this
   platform is built around — see `scripts/drift-demo.sh` for a live
   demonstration of the same self-heal machinery reverting a much faster,
   manually-introduced change.

2. **Argo CD UI -> History and Rollback.** Pick a previous sync revision
   directly in the UI. Faster than a `git revert` round-trip, but it
   creates real drift from Git — the cluster now runs something Git
   doesn't describe. Follow it immediately with a `git revert` of the
   underlying commit so Git and cluster state agree again; treat the UI
   rollback as a stopgap, not a substitute for the Git operation.

3. **`kubectl rollout undo` (emergency only).** Works instantly and needs
   no Git access, which is exactly why it's the emergency option and not
   the default: with `selfHeal: true` set on every `Application`
   (`bootstrap/root-app.yaml` and every `platform/*/application.yaml` and
   `tenants/*/applications.yaml`), Argo CD will notice the Deployment no
   longer matches Git and revert your rollback right back to the broken
   state, typically within one reconciliation cycle. If you ever use this
   under pressure, immediately follow it with a `git revert` — the same
   discipline as option 2, just more urgent.

See `docs/troubleshooting.md` scenario 5 for the closely related failure
mode where Argo CD and the HPA (not a human) fight over `spec.replicas` —
a different field, the same underlying lesson about `selfHeal` and who
else might legitimately own a field it's watching.
