# Troubleshooting runbook

Eight scenarios, each in the same shape: Symptoms -> Diagnosis -> Cause ->
Fix. Scenarios 2 and 5 are the two most important in this repository —
they map directly to known traps #4 and #1 respectively, and are the two
mistakes most likely to actually happen the first time this platform is
built from scratch.

---

## 1. An Application is stuck `OutOfSync` with a `ComparisonError`

**Symptoms.** In the Argo CD UI the Application is red, status `Unknown`
or `OutOfSync`, with a detail message like `rpc error: code = Unknown
desc = Manifest generation error`.

**Diagnosis.**
```bash
kubectl -n argocd get application <name> -o jsonpath='{.status.conditions}' | jq
kubectl -n argocd logs deploy/argocd-repo-server --tail=100
helm template test charts/webapp -f envs/prod/team-alpha.yaml   # reproduce locally
```

**Cause.** A template syntax error; `values.schema.json` rejecting a
value; a wrong `valueFiles` path; a chart referencing a dependency that
was never fetched; a `targetRevision` pointing at a branch or tag that
doesn't exist.

**Fix.** Reproduce with `helm template` locally first — the error is the
same but far more readable outside Argo CD's wrapping. If it renders fine
locally but fails in Argo CD, the near-universal cause is a relative
`valueFiles` path: Argo CD resolves it from the repository root, not from
the chart's own directory (see `tenants/team-alpha/applications.yaml`'s
`../../envs/dev/team-alpha.yaml` for the pattern this repo actually uses).

---

## 2. Pods start, but every DNS lookup hangs

**Symptoms.** A pod reaches `Running`, readiness passes, but any
name-based request to another service hangs and eventually times out.
Application logs show `Temporary failure in name resolution`.

**Diagnosis.**
```bash
kubectl -n team-alpha run dnstest --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup kubernetes.default
kubectl -n team-alpha get networkpolicy
kubectl -n team-alpha describe networkpolicy default-deny-all
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

**Cause.** The `default-deny-all` NetworkPolicy
(`policyTypes: [Ingress, Egress]`, no rules) blocks *all* egress,
including DNS to `kube-system` on port 53. This is the single most common
mistake the first time a NetworkPolicy default-deny is introduced.

**Fix.** Add an explicit egress allow to `kube-system` on port 53 for
**both** UDP and TCP — see `tenants/team-alpha/networkpolicy.yaml`'s
`allow-dns-egress` policy, which this repository already ships with both
protocols present specifically to avoid this. Missing TCP alone still
breaks any DNS answer too large for one UDP datagram (a Service with many
endpoints, for example) while looking fine for simpler lookups — don't
stop testing at the first successful `nslookup`.

---

## 3. Ingress returns 502 Bad Gateway

**Symptoms.** `curl https://alpha.platform.local` returns nginx's own 502
page. The webapp pods are `Running`.

**Diagnosis.**
```bash
kubectl -n team-alpha get endpoints team-alpha-prod-webapp
kubectl -n team-alpha get svc team-alpha-prod-webapp -o yaml | grep -A3 ports
kubectl -n team-alpha describe pod -l app.kubernetes.io/instance=team-alpha-prod | grep -A5 Readiness
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50
kubectl -n team-alpha port-forward svc/team-alpha-prod-webapp 8000:80   # bypass ingress
```

**Cause.** One of: (1) `endpoints` is empty because the readiness probe
never passes; (2) the Service's `targetPort` doesn't match the
container's actual listening port; (3) the Service's selector doesn't
match the pod's labels; (4) a NetworkPolicy is blocking traffic from
`ingress-nginx`.

**Fix.** An empty endpoints list points straight at (1) or (3). If
endpoints exist and 502 persists, it's (2) or (4) — `port-forward`
straight to the Service splits these two: if that works, the problem is
strictly between ingress-nginx and the Service, i.e. the NetworkPolicy.

---

## 4. `Certificate` never reaches `Ready: True`

**Symptoms.** `kubectl get certificate` shows `READY: False` for hours.
The ingress serves nginx's own default self-signed certificate instead.

**Diagnosis.** Walk the chain in order — the real cause is always at the
last resource that exists:
```bash
kubectl -n team-alpha describe certificate <name>
kubectl -n team-alpha get certificaterequest
kubectl -n team-alpha describe certificaterequest <name>
kubectl -n team-alpha get order
kubectl -n team-alpha describe order <name>
kubectl -n team-alpha get challenge
kubectl -n team-alpha describe challenge <name>
kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

**Cause.** The referenced `ClusterIssuer` doesn't exist or is itself
`Ready: False`; an HTTP-01 challenge that's unreachable from outside; a
wrong DNS-01 API token; the Let's Encrypt rate limit (50 certificates per
domain per week); or a typo in the `cert-manager.io/cluster-issuer`
annotation's issuer name. In this repository specifically, check that
name first — see `docs/bootstrap.md`'s note on the chart defaulting to
`letsencrypt-staging` while the local ClusterIssuer this repo ships is
named `selfsigned`.

**Fix.** The Certificate -> CertificateRequest -> Order -> Challenge chain
always terminates at the real cause on its last existing resource. When
testing against Let's Encrypt for real, always start on the staging
server (`platform/cert-manager/issuers/letsencrypt.yaml` already does) —
its rate limits are far looser, and switching to production is a
one-line change once staging succeeds end to end.

---

## 5. Argo CD and the HPA fight over replica count

**Symptoms.** Replica count oscillates. In the Argo CD UI the Application
repeatedly goes `OutOfSync` on `spec.replicas`, syncs, then drifts again.

**Diagnosis.**
```bash
kubectl -n team-alpha get hpa
kubectl -n argocd get application team-alpha-prod -o jsonpath='{.status.resources}' | jq
kubectl -n team-alpha get deploy team-alpha-prod-webapp -o jsonpath='{.spec.replicas}'
helm template test charts/webapp -f envs/prod/team-alpha.yaml | grep -A2 "replicas:"
```

**Cause.** The chart renders `spec.replicas`, the HPA changes it based on
load, `selfHeal: true` reverts it back to Git's value, and the HPA
changes it again — two controllers, both legitimately trying to own the
same field.

**Fix (correct).** Never render `replicas` at all when autoscaling is
enabled:
```yaml
{{- if not .Values.autoscaling.enabled }}
replicas: {{ .Values.replicaCount }}
{{- end }}
```
`charts/webapp/templates/deployment.yaml` already implements exactly
this, and `charts/webapp/tests/deployment_test.yaml` asserts it directly.
**Fix (workaround, for other fields only).** An `ignoreDifferences` entry
on the Application, or the `compare-options: IgnoreExtraneous`
annotation — but for `replicas` specifically, not rendering the field is
the only fix that doesn't just relocate the fight.

This is one of the strongest interview scenarios in this whole project:
it demonstrates understanding that multiple controllers can legitimately
try to own one field, and that GitOps self-heal is not automatically
correct in every case — it needs to know what it should and shouldn't
own.

---

## 6. A `SealedSecret` won't decrypt

**Symptoms.** A `SealedSecret` exists, but the corresponding `Secret`
never appears. `kubectl describe sealedsecret` shows a decryption error.

**Diagnosis.**
```bash
kubectl -n <namespace> describe sealedsecret <name>
kubectl -n kube-system logs deploy/sealed-secrets-controller --tail=50
kubectl -n kube-system get secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
```

**Cause.** The secret was encrypted with a different cluster's public
key — the most common trigger is `scripts/teardown.sh` followed by a
fresh `make up` + `make bootstrap`, which generates a brand-new keypair —
or the `SealedSecret` was copied into a different namespace than the one
it was sealed for.

**Fix.** Re-seal every secret against the new cluster's public key
(`scripts/seal-secret.sh`), or restore the old private key from a backup
*before* bootstrapping (see `docs/security.md`'s backup procedure). This
is exactly why that backup procedure is described as the single most
critical recovery step in the platform.

---

## 7. A pod fails with `CreateContainerConfigError` after Pod Security Admission is enabled

**Symptoms.** A pod won't start; `describe` shows a policy violation
against the `restricted` profile.

**Diagnosis.**
```bash
kubectl -n team-alpha describe pod <name> | tail -20
kubectl get ns team-alpha -o jsonpath='{.metadata.labels}' | jq
kubectl -n team-alpha get pod <name> -o jsonpath='{.spec.securityContext}' | jq
```

**Cause.** The `restricted` profile requires `runAsNonRoot: true`,
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, and
`seccompProfile.type: RuntimeDefault` — missing any one of them blocks
pod creation outright. `charts/webapp/values.yaml`'s `securityContext`
block ships with the full set already; this scenario is what happens if
a future template change accidentally drops one.

**Fix.** Add whatever's missing back into the chart. To find every
violation ahead of time rather than one at a time: temporarily set the
namespace label to `warn` instead of `enforce` and run
`kubectl apply --dry-run=server` to see every warning at once.

---

## 8. The kind node's disk fills up

**Symptoms.** Pods go `Evicted`, the node carries a
`node.kubernetes.io/disk-pressure` taint, new pods stay `Pending`.

**Diagnosis.**
```bash
kubectl describe node <node> | grep -A5 Conditions
docker exec -it gitops-platform-worker df -h /
docker system df
crictl images   # inside the node
```

**Cause.** A kind node is a Docker container, sharing the host's
filesystem. Repeated local image builds across many iterations pile up
and fill the shared space.

**Fix.** `docker system prune -af` on the host. Inside the nodes,
kubelet's own garbage collection removes unused images eventually, but
its thresholds in kind are conservative — don't rely on it alone.
Preventively: this project's images come from GHCR (see `ci-app.yml`),
so there's rarely a reason to `kind load` a locally-built image into the
cluster at all; avoid making that a habit during iteration.
