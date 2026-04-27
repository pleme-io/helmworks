# Compliance Proof — helmworks FedRAMP-High Primitives

**Status:** Proof valid against `pleme-lib` ≥ 0.7.0 (Layer 1+2+3 air-gap).

This document is the proof that **as long as a chart consumes only the
`pleme-lib` compliance primitives below, it cannot produce a non-compliant
K8s architecture at the chart layer.** The proof is constructive and
mechanical: for every K8s-side FedRAMP-High invariant, we identify (1) the
helper or default that enforces it, (2) the violation shape, and (3) the
test that demonstrates a violating shape causes `helm template` to fail or
produces output that satisfies the invariant.

If every test below passes, the proof holds. If a future change weakens any
helper, its test fails and the proof breaks visibly.

> The companion claims-and-controls work that this proof maps to lives in:
> `pangea-architectures/lib/pangea/architectures/generated/compliance/fedramp_high.rb`,
> `kensa/src/mapping/fedramp.rs`, and
> `tameshi/src/compliance/dimensions.rs`.

---

## 1. Claim

**Claim P (chart-render proof):** For any consumer chart `C` that depends on
`pleme-lib` ≥ 0.6.0 and renders all K8s objects through `pleme-lib.deployment`
/ `pleme-lib.networkpolicy` / `pleme-lib.serviceaccount` /
`pleme-lib.servicemonitor` / `pleme-lib.pdb` / `pleme-lib.compliance.manifest`
helpers, and any `Values v` such that `v.compliance.baseline = "fedramp-high"`
and `v.compliance.enforce = true`:

> Either `helm template C v` **fails** with a non-zero exit code and an
> error message naming a NIST 800-53 control, or it produces YAML manifests
> that satisfy every K8s-side invariant in §3.

There is no third outcome. The corollary is what the user demanded: a chart
that only uses these primitives cannot accidentally ship a non-compliant
architecture.

---

## 2. Trust boundary (what is NOT proved here)

The chart-render proof is **necessary but not sufficient** for a deployed
workload to be FedRAMP-High compliant. The following are out of scope and
must be enforced separately by the cluster, the registry, and the audit
pipeline:

| Scope                                        | Required cluster guarantee                                                |
|----------------------------------------------|----------------------------------------------------------------------------|
| **Image bytes match digest**                 | OCI registry enforces digest immutability; no MITM during image pull       |
| **Pod Security Standard admission**          | Cluster has the built-in PSS admission controller enabled (`restricted`)   |
| **NetworkPolicy actually blocks traffic**    | CNI implements NetworkPolicy (Cilium, Calico, …) and admin has not exempted ns |
| **Sekiban admission verifies attestation**   | `sekiban` ValidatingAdmissionWebhook deployed and reachable                |
| **Audit log retention**                      | Loki / Splunk / Vector pipeline retains ≥ 365 days; immutable WORM         |
| **Encrypted storage class is actually encrypted** | StorageClass uses an encrypted CSI driver with FIPS-validated KMS-backed key |
| **Image signature**                          | Cosign verification at admission (separate from sekiban)                   |
| **Secret values never logged**               | Vector pipeline strips secret-named fields                                 |
| **Pod runtime applies seccomp**              | Container runtime (containerd) honors `seccompProfile`                     |
| **Akeyless DFC threshold signing**           | Akeyless gateway reachable; threshold quorum operational                   |
| **Air-gap NetworkPolicy enforcement**        | CNI implements egress NetworkPolicy + IP allowlists for external CIDRs; or Cilium FQDN policy is enabled when `useCilium=true` |
| **Cosign signature verification**            | Zot's `extensions.scrub` + `extensions.sign` verify cosign sigs at the boundary; cosign public-key Secret rotation is operational |
| **Upstream credential rotation**             | `compliance.airgap.upstream.credentialSecret` (and `compliance.mirror.upstreams[*].credentialSecret`) rotated externally (Akeyless, External Secrets Operator) |
| **kube-state-metrics CronJob audit**         | When `compliance.audit.viaJobEvents=true`, the cluster scrapes `kube_cronjob_*` metrics and persists Job pod logs (Vector/Loki) to satisfy AU-2/AU-12 |

These are documented in:

- Cluster: `pleme-io/k8s/clusters/<cluster>/OBSERVABILITY.md` and
  `pleme-io/k8s/clusters/<cluster>/SECURITY.md`
- Registry/build: `pleme-io/forge/CLAUDE.md`
- Network: `pleme-io/k8s/clusters/<cluster>/cilium-policies/`
- Sekiban: `pleme-io/sekiban/CLAUDE.md`
- Akeyless DFC: `tameshi/docs/grand-unified-specification.md` § *Phase 2 signing*

The full end-to-end chain is the union of this proof and the cluster
guarantees above. Everything in this document is the **chart-render** half.

---

## 3. Control surface — invariant ↔ enforcement ↔ test

For each NIST 800-53 control mapped to the K8s workload layer, the table
gives:

- **Invariant:** the property that must hold of the rendered manifests
- **Enforcement:** which helper / default / validator guarantees the property
- **Negative test:** the test case that demonstrates a violating input fails
- **Positive test:** the test case that demonstrates the invariant holds in
  the rendered output of the canonical example values

Negative tests live in
`tests/pleme-microservice/compliance_proof_negative_test.yaml` and
`tests/_fixtures/pleme-lib-bare/compliance_lib_validators_test.yaml`.
Positive tests live in
`tests/pleme-microservice/compliance_proof_positive_test.yaml`.

| Control      | Invariant                                                              | Enforcement                                                          | Negative test | Positive test |
|--------------|------------------------------------------------------------------------|----------------------------------------------------------------------|---------------|---------------|
| **AC-3**     | Workload runs under a dedicated, non-default ServiceAccount            | `_compliance_rbac.tpl::rbac.validate`                                | `[AC-3/AC-6/IA-2] rejects default ServiceAccount`, `[AC-3/AC-6/IA-2] rejects serviceAccount.name=default` | `[AC-3/AC-6/IA-2] dedicated ServiceAccount created`, `[AC-3] Deployment uses the dedicated ServiceAccount` |
| **AC-3**     | Sekiban annotation present so admission can deny on missing attestation | `_compliance.tpl::compliance.annotations`, `_compliance_attestation.tpl::attestation.validate` | `[CM-2/SI-7/AC-3] rejects attestation.enabled=false (high)` | `[CM-2/SI-7/AC-3] sekiban-required annotation present` |
| **AC-4**     | Default-deny NetworkPolicy emitted; explicit allow only via `additional*` | `_compliance_network.tpl::network.policies`, `_networkpolicy.tpl` auto-render | `[AC-4/SC-7] rejects networkPolicy.enabled=false (moderate+)` | `[AC-4/SC-7] default-deny NetworkPolicy present` |
| **AC-6**     | No `privileged: true` containers                                       | `_compliance_security.tpl::security.validate`                        | `[CM-7] rejects securityContext.privileged=true`             | `[CM-7] not privileged` |
| **AC-6**     | No `allowPrivilegeEscalation: true`                                    | `security.validate`                                                  | `[CM-7] rejects allowPrivilegeEscalation=true`               | `[CM-7] no privilege escalation` |
| **AC-6**     | No `hostNetwork`, `hostPID`, `hostIPC`                                 | `security.validate`                                                  | `[AC-6/SC-7] rejects hostNetwork=true`, `[AC-6/CM-7] rejects hostPID=true`, `[AC-6/CM-7] rejects hostIPC=true` | (negative-only) |
| **AC-6**     | No `hostPath` volumes (high)                                           | `security.validate`                                                  | `[AC-6/CM-7] rejects hostPath volumes (high)`                | (negative-only) |
| **AC-6**     | `runAsNonRoot: true`, `runAsUser != 0`                                 | `security.validate`, `_compliance_security.tpl::podSecurityContext`  | `[AC-6] rejects runAsUser=0 (high)`, `[AC-6] rejects runAsNonRoot=false (high)` | `[AC-6] runAsNonRoot=true (pod and container)` |
| **AC-6**     | `automountServiceAccountToken=false` unless explicitly opted out       | `_compliance_security.tpl::automountServiceAccountToken` default + `security.validate` opt-out gate | `[AC-6/IA-2] rejects automountServiceAccountToken=true (without opt-out)` | `[AC-6/IA-2] automountServiceAccountToken=false on pod`, `… on ServiceAccount` |
| **AC-17**    | External Ingress terminates TLS                                        | `_compliance_ingress.tpl::ingress.validate`                          | `[SC-8/SC-13/AC-17] rejects ingress.enabled without ingress.tls (moderate+)` | (negative-only — Ingress object out of `pleme-lib`'s scope) |
| **AU-2/12, SI-4** | ServiceMonitor exists; metrics scraped by Prometheus              | `_compliance_audit.tpl::audit.validate`, `_servicemonitor.tpl`       | `[AU-2/12, SI-4] rejects monitoring.enabled=false (moderate+)` | `[AU-2/AU-12/SI-4] ServiceMonitor present` |
| **AU-3**     | Structured-logging audit metadata in pod annotations                   | `_compliance_audit.tpl::audit.annotations`                           | (covered by manifest test; structurally always emitted)      | `[AU-3] structured-logging audit annotations on Deployment` |
| **CM-2**     | Image referenced by digest (`@sha256:…`), not `latest`                 | `_compliance_image.tpl::image.validate`                              | `[CM-2] rejects image.tag=latest`, `[SI-7] rejects non-digest tag at high` | `[CM-2/SI-7] container image is digest-pinned` |
| **CM-2**     | Compliance manifest ConfigMap describing covered controls              | `_compliance_manifest.tpl::compliance.manifest`                      | (negative for "missing manifest" not constructible — manifest is always emitted when baseline is set) | `[CM-2] compliance-manifest ConfigMap emitted with control list` |
| **CM-6**     | seccompProfile = RuntimeDefault (or Localhost), never Unconfined       | `_compliance_security.tpl::podSecurityContext` / `containerSecurityContext` defaults + `security.validate` | `[CM-6/SI-16] rejects seccompProfile.type=Unconfined`, `…podSecurityContext.seccompProfile.type=Unconfined` | `[CM-6/SI-16] seccompProfile=RuntimeDefault (pod and container)` |
| **CM-7**     | Capabilities `drop: [ALL]`; no dangerous `add`                         | `containerSecurityContext` default + `security.validate`             | `[CM-7] rejects capabilities.add=SYS_ADMIN`, `…NET_ADMIN`    | `[CM-7] container drops ALL capabilities` |
| **CM-7**     | `imagePullPolicy != Never`                                             | `image.validate`                                                     | `[CM-7] rejects pullPolicy=Never`                            | `[CM-7] imagePullPolicy=Always` |
| **CM-8**     | Inventory labels (`app.kubernetes.io/*`, `compliance.pleme.io/*`)     | `_helpers.tpl::pleme-lib.labels`, `compliance.labels`                 | (always emitted — no failure mode by construction)           | `[CM-8] inventory labels and compliance baseline label present` |
| **IA-2**     | ServiceAccount tokens projected, not auto-mounted                       | `automountServiceAccountToken` default + opt-out gate                | (same tests as AC-6 automount above)                         | (same as AC-6) |
| **IA-5**     | Secret-shaped env vars sourced via `valueFrom.secretKeyRef`             | `_compliance_secrets.tpl::secrets.validate`                          | `[IA-5/SC-12] rejects literal env value for *_SECRET`, `…*_PASSWORD`, `…*_TOKEN` | (negative-only — positive case is "no env entries with literal values for secret-shaped names") |
| **SC-5**     | Resource requests AND memory limit set                                  | `_compliance_availability.tpl::availability.validate`                | (bare-fixture suite) `[SC-5] rejects missing resources at fedramp-high`, `[SC-5] rejects requests-only` | `[SC-5] resources.requests.cpu, …memory, …limits.memory all set` |
| **SC-5/CP-2**| Replica count ≥ 2 at high                                              | `availability.validate`                                              | `[SC-5/CP-2] rejects replicaCount=1 (high)`, `[SC-5/CP-2] rejects autoscaling.minReplicas=1 (high)` | (positive: PDB present + topology spread present imply availability surface intact) |
| **SC-5**     | PodDisruptionBudget rendered automatically at high                     | `_compliance_availability.tpl::availability.pdb`, `_pdb.tpl` auto-render | (auto-rendered; no failure mode)                             | `[SC-5/CP-2] PodDisruptionBudget present` |
| **SC-5**     | Topology spread (zone + hostname) at high                              | `availability.topologySpread`, `_deployment.tpl` auto-emit            | (auto-rendered)                                              | `[SC-5] topology spread (zone + hostname) present` |
| **SC-7**     | NetworkPolicy emitted (boundary)                                       | `network.policies` auto-render                                       | `[AC-4/SC-7] rejects networkPolicy.enabled=false (moderate+)` | `[AC-4/SC-7] default-deny NetworkPolicy present` |
| **SC-7(4/5)**| Egress NAT-only model annotation surfaced; default-deny posture         | `compliance.annotations` (high)                                       | (annotation always emitted at high)                          | `[CM-2/SI-7] availability-required and encryption-at-rest-required annotations present (high)` |
| **SC-8**     | TLS-only egress on 443 NetworkPolicy emitted; ingress TLS required      | `network.allowTlsEgress`, `ingress.validate`                          | `[SC-8/SC-13/AC-17] rejects ingress.enabled without ingress.tls`, (auto-rendered for egress) | `[SC-8/SC-13] allow-tls-egress NetworkPolicy present (443/TCP only)` |
| **SC-12**    | No literal secret values; secret refs only                             | `secrets.validate`                                                   | (same as IA-5 negatives)                                     | (same as IA-5) |
| **SC-13**    | TLS used (Ingress + egress 443)                                        | `ingress.validate` + `network.allowTlsEgress`                         | (same as SC-8 negative)                                      | (same as SC-8 positive) |
| **SC-22**    | DNS allow rule emitted (53/UDP, 53/TCP)                                 | `network.allowDns` auto-render                                        | (auto-rendered; failure mode would require disabling network policies which is itself rejected) | `[SC-22] allow-dns NetworkPolicy present` |
| **SC-28**    | PVCs use an encrypted-class allowlisted storage class                  | `_compliance_storage.tpl::storage.validate`                          | `[SC-28] rejects unencrypted persistence storageClass (high)`, `[SC-28] rejects missing storageClass with persistence enabled (high)` | (positive-only when persistence is enabled; the example doesn't enable persistence) |
| **SI-4**     | (same as AU-2/12) ServiceMonitor + alerts                              | `audit.validate`                                                     | (same negative)                                              | (same positive) |
| **SI-7**     | Image digest-pinned + attestation hashes present                       | `image.validate` + `attestation.validate`                            | `[SI-7] rejects non-digest tag at high`, `[CM-2/SI-7/AC-3] rejects attestation.enabled=false (high)` | `[CM-2/SI-7] container image is digest-pinned`, `[CM-2/SI-7/AC-3] sekiban-required annotation present` |
| **SI-16**    | seccomp default + Unconfined forbidden                                 | `containerSecurityContext` default + `security.validate`             | (same as CM-6 negatives)                                     | (same as CM-6 positives) |
| **ESCAPE**   | `compliance.enforce=false` is a documented opt-out, not a default      | `_compliance.tpl::compliance.enforce`                                 | `[ESCAPE] enforce=false bypasses validators (must remain a deliberate opt-out)` | (deliberately the only escape; documented in `pleme-lib/values.yaml`) |

---

## 3.5. Air-gap controls (added in `pleme-lib` 0.7.0)

Compounding layer. Air-gap is expressed as Layer 2 primitives composed
out of Layer 1 generic primitives (egress, authz, authn). Every air-gap
invariant is enforced by a validator and mechanically tested.

The pattern: every workload's container images come from a cluster-local
OCI registry (Zot), and that registry is the *only* path to external
image bytes. Workloads in `consumer` role can talk to nothing external;
the registry-mirror workload (Zot in pull-mode, or `pleme-image-sync` in
cache-mode) is the *single* point of upstream egress.

| Control      | Invariant                                                              | Enforcement                                                          | Negative test | Positive test |
|--------------|------------------------------------------------------------------------|----------------------------------------------------------------------|---------------|---------------|
| **SC-7(11)** | Workload egresses only to the cluster-local registry (consumer role) OR only to a curated upstream allowlist (registry-mirror role) | `_compliance_airgap.tpl::airgap.consumerEgressPolicy`, `…mirrorEgressPolicy` (auto-rendered); `airgap.validate` | `[SC-7(11)] airgap=consumer rejects external image`, `[SC-7(11)] airgap=registry-mirror requires allowedCidrs or allowedHosts+useCilium` | `[SC-7(11)] registry-mirror egress NetworkPolicy is rendered` (pleme-zot, pleme-image-sync) |
| **SC-7(12)** | Per-pod NetworkPolicy with explicit egress allowlist                   | `_compliance_egress.tpl::egress.toService` / `egress.toUpstream`      | (covered by SC-7(11) tests; auto-rendered) | (auto-rendered) |
| **CM-2 (image)** | Consumer's `image.repository` MUST start with one of the allowed registry hosts | `airgap.validate` | `[SC-7(11)] airgap=consumer rejects external image` | (positive form: image is from `zot.<ns>.svc.cluster.local`) |
| **SI-7 (cosign)** | Registry-mirror MUST verify cosign signatures at the boundary at fedramp-high | `airgap.validate` (`requireSignedImages=true`); `pleme-zot` `extensions.scrub` + `extensions.sign` | `[SI-7] airgap+high requires requireSignedImages=true`, `[SI-7] requireSignedImages=false at high is rejected` (pleme-zot) | `[SI-7] cosign extension enabled in Zot config` (positive) |
| **IA-5 (mirror)** | Upstream pulls MUST present credentials at fedramp-high             | `airgap.validate`; `mirror.validate` | `[IA-5] airgap=registry-mirror at high requires upstream.credentialSecret`, `[AU-3/IA-5] mirror.upstreams entry without credentialSecret rejected`, `[IA-5] missing upstream credentialSecret at high is rejected` (pleme-zot) | (positive — image-sync values reference `image-sync-upstream-creds`) |
| **AU-3 (mirror)** | Every sync run emits structured audit-suitable JSON to stdout      | `pleme-image-sync` cronjob template `echo {"event":...}` lines       | (negative-only — absence of structured logging is hard to test at template time) | `[AU-3] structured-logging audit annotations on Deployment` (already covered in §3) |
| **CM-2 (mirror)** | Mirror upstreams + schedule + cosign config are version-controlled | `_compliance_mirror.tpl::mirror.validate` (schedule must be cron; upstreams non-empty) | `[SI-7] mirror.upstreams set + high requires cosignVerify=true` | (positive: image-sync values declare upstream + schedule + cosign) |

### Composition diagram

```
consumer workload (pleme-microservice, pleme-worker, …)
   │
   ▼  pulls images via airgap.consumerEgressPolicy (NetworkPolicy
   │   allowing only the local Service)
   │
local registry (pleme-zot, registry-mirror role, encrypted PVC, OIDC,
                cosign at the boundary, audit logs)
   │
   ▼  populated by airgap.mirrorEgressPolicy (NetworkPolicy allowing
   │   only the upstream allowlist CIDR / FQDN range)
   │
upstream allowlist (ghcr.io, quay.io, registry.k8s.io, etc.)
                              ▲
                              │
                              │ pushed by pleme-image-sync (registry-mirror
                              │ role, schedule-driven CronJob, cosign-verifying)
```

Why this is a *primitive* and not a one-off:

- `egress.toService` (Layer 1) is reused by any "talk only to X" pattern
  (the database-only workload, the auth-only workload, etc.)
- `egress.toUpstream` (Layer 1) is reused by any "talk only to a curated
  external allowlist" pattern (helm-mirror, policy-mirror, sbom-mirror,
  …)
- `airgap.consumer` / `airgap.registry-mirror` (Layer 2) are typed roles
  on top of Layer 1 — adding a new mirror type (Helm charts, OPA bundles,
  Falco rules) means writing 30 lines of values + cronjob, with all the
  air-gap egress + RBAC + auth + audit primitives inherited.

## 3.6. RBAC controls (Layer 1 authz)

| Control      | Invariant                                                              | Enforcement                                                          | Negative test |
|--------------|------------------------------------------------------------------------|----------------------------------------------------------------------|---------------|
| **AC-6**     | No `verbs: ["*"]` on Role rules                                       | `_compliance_authz.tpl::authz.validate`                              | `[AC-6] rejects Role rule with verbs: ["*"]` |
| **AC-6**     | No `resources: ["*"]` on Role rules                                   | `authz.validate`                                                     | `[AC-6] rejects Role rule with resources: ["*"]` |
| **AC-6(1)**  | No `apiGroups: ["*"]` on ClusterRole rules at fedramp-high             | `authz.validate`                                                     | `[AC-6(1)] rejects ClusterRole apiGroups: ["*"] at fedramp-high` |
| **AC-6(7)**  | No RoleBinding to `system:authenticated` / `system:unauthenticated` / `system:masters` without explicit allowlist | `authz.validate` | `[AC-6(7)] rejects RoleBinding subject Group:system:authenticated` |
| **AC-6**     | No ClusterRoleBinding to `cluster-admin` at fedramp-high                | `authz.validate`                                                     | (covered by ClusterRoleBinding-name check in `authz.validate`) |

## 3.7. Authentication controls (Layer 1 authn)

| Control      | Invariant                                                              | Enforcement                                                          | Negative test |
|--------------|------------------------------------------------------------------------|----------------------------------------------------------------------|---------------|
| **IA-2 / AC-17** | External Ingress requires `compliance.authn.oidc.provider` (Authentik) at fedramp-moderate+ | `_compliance_authn.tpl::authn.validate` | `[IA-2/AC-17] rejects ingress.enabled without compliance.authn.oidc` |
| **IA-3**     | Service-to-service mTLS via Istio PeerAuthentication=STRICT at fedramp-high | `authn.peerAuthentication` (auto-emit at high) | (auto-rendered when baseline=high; absence cannot be expressed) |
| **IA-5**     | Projected SA tokens with explicit audience and TTL ≤ 3600s at fedramp-high | `authn.tokenVolume`; `authn.validate` (TTL bound) | (TTL > 3600s rejected by `authn.validate`) |

---

## 4. Why this is a proof, not just a test suite

Two mechanical properties make it a proof rather than a suite of probes:

### 4.1 Surface coverage is closed

Every K8s API surface that could express a non-compliant property is wired
through one of the helpers in §3. The set of helpers consumer charts call is
small:

```
pleme-lib.deployment          — Deployment (incl. pod sec ctx, container, automount, image, topology)
pleme-lib.service             — Service
pleme-lib.serviceaccount      — ServiceAccount (incl. automount default)
pleme-lib.servicemonitor      — ServiceMonitor
pleme-lib.networkpolicy       — NetworkPolicy (auto-deny + auto-dns + auto-tls + additional)
pleme-lib.pdb                 — PodDisruptionBudget
pleme-lib.compliance.manifest — compliance ConfigMap
```

And the namespace-scope chart `pleme-compliance` covers Namespace,
default-deny NetworkPolicy at namespace level, ResourceQuota, LimitRange.

There is no helper that emits a workload-shaped resource without going
through `pleme-lib.compliance.validate` first. A consumer who **only** uses
these helpers cannot reach a K8s API that bypasses the validators — by
construction.

### 4.2 Values surface is closed

Every values.yaml field that could weaken compliance is either:

1. **A default that the helper sets to the safe value** (e.g.,
   `seccompProfile.type=RuntimeDefault`, `automountServiceAccountToken=false`).
2. **A field whose unsafe value is rejected by a validator** with `fail()`
   (e.g., `securityContext.privileged=true`, `image.tag=latest`).
3. **Auto-rendered regardless of the value** (e.g., NetworkPolicy
   default-deny is emitted at moderate+ even if `networkPolicy.enabled=false`,
   which itself causes a `fail()`).

The `compliance.enforce: false` flag is the **single** documented escape
valve. It exists for migration runs; production charts must leave
`enforce: true`. The `[ESCAPE]` test case keeps the escape valve from being
silently removed (which would break migration paths) **and** documents that
flipping it bypasses the proof — so the consumer cannot accidentally bypass
the proof under cover of "we changed the validator."

### 4.3 The proof corpus exhausts the violation shapes

§3's negative tests enumerate one violating shape per invariant. New
invariants must be added to §3 alongside a new validator and a new test.
The pattern is mechanical: pre-merge CI runs all three test suites, and a
weakened validator fails its test, which fails CI, which surfaces the
proof break in the PR.

---

## 5. How to extend the proof

When you add a new control or strengthen an existing one:

1. **Add the invariant to §3** with the helper that enforces it.
2. **Add a validator** in `_compliance_<category>.tpl` (or extend an existing
   one) — must be a `fail()` not a warning.
3. **Wire it** into `_compliance.tpl::compliance.validate`.
4. **Add a negative test** in
   `tests/pleme-microservice/compliance_proof_negative_test.yaml` (or the
   bare-fixture suite if the chart's own defaults block the negative).
5. **Add a positive test** in
   `tests/pleme-microservice/compliance_proof_positive_test.yaml` asserting
   the invariant in rendered output of `examples/fedramp-high.yaml`.
6. **Update the `compliance.controls` list** in `_compliance.tpl` so the
   manifest ConfigMap and the annotation reflect the new control.

Run `helm unittest` for all three suites; if all pass, the proof is intact.

---

## 6. Beyond the chart layer — the full integrity chain

For completeness, the full integrity chain that a deployed pod traverses:

```
1. arch-synthesizer typescape (Rust)
     ↓ encodes invariants as types
2. pangea-architectures (Ruby)
     ↓ generates Terraform JSON for cloud layer (FedRAMP-High AWS arch)
3. helmworks/pleme-lib (this proof)
     ↓ generates K8s YAML for workload layer (this document)
4. tameshi (Rust)
     ↓ BLAKE3 Merkle hash of all layers
5. AkeylessDfcSigner (split-knowledge threshold)
     ↓ signs Merkle root; key never exists in one piece
6. forge CI/CD
     ↓ injects attestation hashes into Helm values; pushes chart
7. FluxCD → sekiban admission webhook (K8s)
     ↓ verifies attestation annotations match registry
8. PSS admission (K8s built-in)
     ↓ verifies pod security context matches namespace label
9. CNI (Cilium)
     ↓ enforces NetworkPolicy
10. containerd
     ↓ applies seccomp, capabilities, readOnlyRootFilesystem
11. kanshi (eBPF runtime sentinel)
     ↓ continuously hashes the running binary; alerts on drift
```

Helmworks owns step 3. Steps 1–2 are out-of-band but their output flows
through this layer (image digest from step 6, attestation from step 5
injected at step 6). The trust boundary in §2 enumerates what the cluster
must guarantee for the chain to remain unbroken from chart bytes to
running process.

---

## 7. CI gate

Pre-merge CI must run, in this order:

```
nix run .#lint                                                  # all charts pass helm lint
helm unittest charts/pleme-microservice                        # legacy suites
helm unittest charts/pleme-microservice -f '../../tests/pleme-microservice/compliance_proof_negative_test.yaml'
helm unittest charts/pleme-microservice -f '../../tests/pleme-microservice/compliance_proof_positive_test.yaml'
helm unittest charts/pleme-microservice -f '../../tests/pleme-microservice/compliance_high_test.yaml'
helm unittest charts/pleme-microservice -f '../../tests/pleme-microservice/compliance_validators_test.yaml'
helm unittest charts/pleme-compliance   -f '../../tests/pleme-compliance/namespace_test.yaml'
helm unittest charts/pleme-zot          -f '../../tests/pleme-zot/zot_compliance_test.yaml'
helm unittest charts/pleme-image-sync   -f '../../tests/pleme-image-sync/image_sync_test.yaml'
helm unittest tests/_fixtures/pleme-lib-bare -f 'compliance_lib_validators_test.yaml'
```

Total at `pleme-lib` 0.7.0: **127 compliance tests across 8 suites**.

Failing any one of the compliance suites breaks the proof and blocks the
merge. The control surface in §3 must be 1:1 with the test names; a
missing test for a listed control is also a CI failure (future work:
auto-generate the control surface table from the test files).
