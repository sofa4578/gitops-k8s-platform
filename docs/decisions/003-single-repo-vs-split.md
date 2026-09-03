# ADR 003: One repository for platform, tenants and application code

## Context

This project has three layers with different owners in a real
organization: the platform team (`platform/`, `bootstrap/`, `kind/`), the
tenant teams (`tenants/`, `envs/`), and the application team
(`src/webapp/`, `charts/webapp/`). Each layer could live in its own
repository — a common pattern once an organization has enough distinct
teams and release cadences to justify the coordination overhead. At the
scale of one platform engineer and two example tenants, this project
had to pick one option, and the choice should generalize to a defensible
answer, not just be "whatever was easiest for a portfolio."

## Decision

Keep everything in a single repository (`gitops-k8s-platform`), with
directory boundaries (`platform/`, `tenants/`, `charts/`, `src/`)
standing in for what would be repository boundaries at larger scale.
Argo CD's `AppProject` and per-directory `CODEOWNERS` entries enforce the
same access boundaries a repo split would, without the operational cost
of keeping N repositories, N sets of branch protection rules, and N CI
configurations in sync.

## Alternatives considered

- **Three repositories** (`platform-gitops`, `tenant-configs`,
  `webapp`), with Argo CD `Application` sources pointing across
  repositories. Mirrors how a real multi-team organization is more
  likely to end up structured, and lets each team set its own branch
  protection and review requirements without touching anyone else's
  rules. Rejected for this project's actual scale: a single engineer
  playing every role gets no benefit from repository-level isolation and
  pays a real cost in cross-repository version pinning (which commit of
  `tenant-configs` was actually deployed alongside which commit of
  `webapp`?) and in scattering the story of the project across three
  places a reviewer would need to open.
- **Two repositories** (platform+tenants together, app code separate).
  A middle ground — app code genuinely does have a different release
  cadence (frequent) than platform/tenant config (infrequent). Rejected
  for the same reason as the three-repo split, just less severely: at
  this scale the coordination cost still outweighs the benefit, though
  this is the split most likely to happen first if the team ever grows
  past a handful of engineers.

## Consequences

- `CODEOWNERS` and Argo CD's `AppProject.sourceRepos` do the access-control
  job repository boundaries would otherwise do — a reviewer can trust
  `git blame` on `platform/` and `charts/` the same way they'd trust "this
  is in the platform-team repo" in a split setup.
- Every commit touches one Git history, which makes this project's own
  README and commit log a straightforward, complete narrative — valuable
  specifically because this is a portfolio artifact meant to be read start
  to finish.
- The tradeoff is real and worth stating honestly: application code
  changes (frequent, per-feature) and platform changes (rare, high-review)
  share one `main` branch and one set of CI workflows. `ci-app.yml` and
  `ci-manifests.yml` are already split by path trigger specifically to
  keep these two cadences from blocking each other in CI, which is the
  first thing that would need to scale further in a real multi-team
  version of this repository.
- If tenant count or team count grew significantly, the first split to
  make is `tenants/` into its own repository per the two-repo alternative
  above — `envs/` and `charts/webapp` would follow only if application
  release cadence diverged enough to justify it.
