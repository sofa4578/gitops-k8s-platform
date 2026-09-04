## What changed

<!-- Describe the change and why it's needed. -->

## Local validation run

- [ ] `yamllint -c .yamllint.yaml .`
- [ ] `helm lint charts/webapp -f charts/webapp/ci-values.yaml`
- [ ] `helm unittest charts/webapp`
- [ ] `cd src/webapp && pytest -q tests/`

<!-- Check only what applies to this change; delete lines that don't apply. -->

## Checklist

- [ ] No plaintext secret was added (secrets exist only as SealedSecret resources)
- [ ] No image tag is `latest` — every version is pinned exactly
- [ ] Related issue linked below (if any)

Closes #
