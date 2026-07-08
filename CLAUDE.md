# Helmworks

> **★★★ CSE / Knowable Construction.** This repo operates under **Constructive Substrate Engineering** — canonical specification at [`pleme-io/theory/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md`](https://github.com/pleme-io/theory/blob/main/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md). The Compounding Directive (operational rules: solve once, load-bearing fixes only, idiom-first, models stay current, direction beats velocity) is in the org-level pleme-io/CLAUDE.md ★★★ section. Read both before non-trivial changes.


Reusable Helm chart library for pleme-io internal services.

## Structure

```
charts/
  pleme-lib/              # Library chart (type: library) — shared named templates
  pleme-microservice/     # HTTP service (REST/GraphQL/gRPC)
  pleme-worker/           # Background worker (no Service)
  pleme-web/              # Frontend + BFF (HTTP + WebSocket)
  pleme-cronjob/          # Scheduled jobs
  pleme-migration/        # Shinka DatabaseMigration CRD
  pleme-operator/         # K8s operator with RBAC

tests/                    # helm-unittest suites
examples/                 # Example values files per service
nix/                      # Nix build helpers (consumed by flake.nix)
```

## Nix Apps

All chart lifecycle operations are `nix run` commands:

| Command | Description |
|---------|-------------|
| `nix run .#lint` | Lint all charts |
| `nix run .#lint:pleme-microservice` | Lint a specific chart |
| `nix run .#package` | Package all charts to `dist/` |
| `nix run .#package:pleme-microservice` | Package a specific chart |
| `nix run .#push` | Push all charts to OCI registry |
| `nix run .#push:pleme-microservice` | Push a specific chart |
| `nix run .#release` | Full lifecycle: lint + package + push |
| `nix run .#release:pleme-microservice` | Release a specific chart |
| `nix run .#template -- pleme-microservice examples/releases.yaml` | Render templates |

**Auto-release (CI, default-on).** On every push to `main`, GitHub Actions
(`.github/workflows/auto-release.yml` → substrate's
`helm-monorepo-auto-release` reusable) runs `nix run .#release` and publishes
every chart whose hand-bumped `Chart.yaml` version is not yet on
`oci://ghcr.io/pleme-io/charts` (404-idempotent — already-published versions are
skipped). There is **no auto-bump**: a chart monorepo has no single version, so
bumping a chart's `Chart.yaml` version in its own commit is the act that ships it
on merge. The `nix run` commands above remain the local / fallback path. Package
visibility is not touched by CI — a private chart's package is set private once
out-of-band. Seven digest-substituted charts (cartorio / lacre / openclaw-*)
carry `annotations: { pleme.io/oci-auto-release: "false" }` so forge's
`discover_charts` skips them (they pin an all-zero placeholder digest a separate
flow substitutes — they can't publish as generic library charts).

**In-tree dependency constraints are floor-only (`>=X.Y.Z`), never ceilinged.**
Every `file://../<chart>` dependency resolves to exactly one chart — the
in-tree one — so a ceiling (`<0.19.0`, `~0.1.0`, `0.1.x`) is not a safety
device; it is a hand-sync tripwire that strands every consumer the moment the
dep's version crosses it. That tripwire fired twice: 017375a (2026-06-02,
98 charts pinned `~0.15.0` while pleme-lib was 0.18.0) re-armed it as a
per-minor pin, and the pleme-lib 0.19.0/0.20.0 bumps (a553074/d0f135b,
2026-06-07) tripped it again — 98/114 charts red at `helm dependency update`
across three days of auto-release runs. Floors record the oldest version a
consumer was verified against; lockstep comes from the monorepo itself —
release-time `helm dependency update` always vendors the in-tree version into
the published .tgz, and helm-unittest catches real template breakage at the
consumer. Exact pins on **remote** deps (oci:// / https:// upstreams) are the
opposite case and stay exact per the hermetic-supply-chain posture below.

**Remote-subchart dependency resolution (release-time, not vendored).** The 15
wrapper charts that pull a third-party upstream subchart (lareira-vm-stack →
victoria-metrics-k8s-stack, lareira-cert-manager, lareira-authentik, the
keda/kyverno/falco/ingress-nginx/external-secrets/policy-controller/trivy/
kubescape wrappers, pleme-arc-*) do **not** vendor that subchart in git
(`.gitignore` excludes `charts/*/charts/` + `charts/*/*.tgz`), so `nix run
.#release` fetches it from the upstream `*.github.io` / OCI repo at release time.
forge ≥ `5a30818` runs every `helm dependency update` under a hard 240s cap + 1
retry (`run_program_timed`), so a slow/down upstream (victoriametrics wedged run
26868152070) fails that one chart cleanly and `release_all` continues, instead of
hanging the whole monorepo release. **Destination (not yet built):** a hermetic
supply chain — mirror these upstream subcharts into `oci://ghcr.io/pleme-io/charts`
once and re-point each wrapper's dep at the pleme-io registry, so release never
depends on third-party repo uptime. Until then the bounded fetch is the floor,
not the ceiling; a genuinely-down upstream still red-flags its chart for retry.

## Chart Architecture

**pleme-lib** is a library chart providing named templates:
- `pleme-lib.deployment` — standard Deployment
- `pleme-lib.service` — ClusterIP Service
- `pleme-lib.serviceaccount` — ServiceAccount (IRSA-ready via `serviceAccount.annotations`)
- `pleme-lib.servicemonitor` — Prometheus ServiceMonitor
- `pleme-lib.networkpolicy` — deny-all + allow-dns + allow-prometheus
- `pleme-lib.pdb` — PodDisruptionBudget
- `pleme-lib.hpa` — HorizontalPodAutoscaler
- `pleme-lib.tieredConfig.*` — shikumi tiered progressive-discovery config as reconciled Helm (enjulho: config-as-Helm, added v0.39.0). Renders a service's operator-overlay tiers from one typed `.Values.config` block: `pleme-lib.tieredConfig.configMap` (the **file tier** — a reconciled ConfigMap the shikumi `ConfigStore` discovers + hot-reloads, keyed `<app>.yaml`), `pleme-lib.tieredConfig.env` (the **env tier** `<PREFIX>_` overrides + the **discovered tier** `POD_NAMESPACE`/`POD_NAME` downward API, as `env:` list-items), `pleme-lib.tieredConfig.volume` / `pleme-lib.tieredConfig.volumeMount` (mount the ConfigMap at the ConfigStore path). **SECRET BOUNDARY: never renders a secret** — passwords/tokens stay on the cofre / `secretKeyRef` path. Values are schema-shaped to the service's `TieredConfig` struct; the mixin header documents the mapping. Consumers: `pangea-operator` chart (destination file tier, default-off) + engenho's chart (live file tier). Tested by `tests/_fixtures/pleme-lib-bare/tiered_config_test.yaml` (verification matrix over both services).
- `pleme-lib.karpenterNodePool` / `pleme-lib.karpenterEC2NodeClass` — Karpenter primitives, iterate values maps for multi-pool charts (added v0.6.0)
- `pleme-lib.namespacedRBAC` — namespace-scoped Role + RoleBinding pairs from a values map (added v0.6.0)
- `pleme-lib.clusterRBAC` — cluster-scoped ClusterRole (+ ClusterRoleBinding) pairs from `.Values.rbac.clusterRoles`; `aggregateLabels` slot for crossplane aggregation, `binding: false` for aggregation-only, Group/User subjects (added v0.18.0)
- `pleme-lib.serviceAccounts` — multiple ServiceAccounts from a `.Values.serviceAccounts` map (sibling of the single-SA `pleme-lib.serviceaccount`) (added v0.18.0)
- `pleme-lib.externalSecret` — External Secrets Operator ExternalSecret resources from a values map; defaults to `cluster-secret-store` (override per entry) (added v0.6.0)
- **Crossplane substrate** (full v1+v2 vocabulary, rendered from `.Values.crossplane.*` maps; added v0.17.0). Each is a no-op on empty map, composes labels + the annotations passthrough, fail()s on missing required fields, and is cluster-scoped except `Usage` (namespaced):
  - `pleme-lib.crossplaneProvider` — `Provider` (+ folded IRSA `DeploymentRuntimeConfig` when `irsaRoleArn` set)
  - `pleme-lib.crossplaneProviderConfig` — `ProviderConfig` (namespaced, v2) / `ClusterProviderConfig` (cluster-scoped) via `cluster:` toggle; per-family `apiVersion` required; optional `namespace:`; `credentials.source` or full `spec:` escape hatch (ClusterProviderConfig split added v0.20.0)
  - `pleme-lib.crossplaneFunction` — `Function`
  - `pleme-lib.crossplaneConfiguration` — `Configuration` (XRD+Composition bundle package)
  - `pleme-lib.crossplaneDeploymentRuntimeConfig` — standalone `DeploymentRuntimeConfig` (IRSA / SA-attach / replicas shortcuts + full passthrough)
  - `pleme-lib.crossplaneCompositeResourceDefinition` (alias `pleme-lib.crossplaneXRD`) — `CompositeResourceDefinition` (apiextensions v2 default; `/v1` toggle; `scope` + claimNames/connectionSecretKeys invariants; openAPIV3Schema passthrough)
  - `pleme-lib.crossplaneComposition` — `Composition` (function-pipeline-only; opaque per-step input)
  - `pleme-lib.crossplaneEnvironmentConfig` — `EnvironmentConfig` (cluster-scoped data bag)
  - `pleme-lib.crossplaneUsage` — `Usage` (namespaced) / `ClusterUsage` (cluster) via `cluster:`
  - `pleme-lib.crossplaneManagedResourceActivationPolicy` (alias `pleme-lib.crossplaneMRAP`) — `ManagedResourceActivationPolicy` (Crossplane v2 scope-by-default; `activate` glob-list keeps only used MRs served → cuts the apiserver `/openapi/v2` full-merge cost; `apiVersion` overridable; fail()s on empty `activate`) (added v0.19.0)
  - `pleme-lib.crossplaneOperation` / `crossplaneCronOperation` / `crossplaneWatchOperation` — `ops.crossplane.io/v1alpha1` (ALPHA, feature-gated, opt-in)
  - `pleme-lib.crossplaneAnnotations` / `crossplanePackage` — helpers (engine-neutral annotations merge; package-string resolver with `fail()` guard)

Application charts invoke these via `{{- include "pleme-lib.deployment" . }}`.

Attestation templates:
- `pleme-lib.attestationAnnotations` — sekiban.pleme.io/* integrity annotations
- `pleme-lib.resourceAnnotations` — combined attestation + user annotations

## Attestation Framework

All charts support integrity attestation via `attestation.*` values:

```yaml
attestation:
  enabled: true
  signature: "blake3:abc..."          # Master signature
  certificationHash: "blake3:def..."  # Product certification hash
  complianceHash: "blake3:ghi..."     # Compliance test result hash
  changesetHash: "blake3:jkl..."      # Changeset integrity hash
```

When enabled, `sekiban.pleme.io/*` annotations are added to Deployment and Service
metadata. These are verified by sekiban's ValidatingAdmissionWebhook.

Hashes are computed by tameshi and injected by forge CI/CD during release.
Do NOT set these manually.

## Security Baseline (enforced)

All charts enforce:
- `runAsNonRoot: true`, `runAsUser: 1000`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`

## Compliance overlays — canonical surface (pleme-lib ≥ 0.10.0)

`pleme-lib` 0.10.0+ ships a typed overlay registry. A consumer chart's
entire compliance posture is one declaration:

```yaml
compliance:
  overlays: [dod-il5]
  # cascades fedramp-high, airgap-consumer, supplychain, fips
```

The overlay registry is the **canonical surface**. Legacy values
(`compliance.baseline`, `compliance.airgap.enabled`, …) still work via
a back-compat shim that synthesizes the overlay list automatically —
existing charts don't need touching.

**Registered overlays** (in `_overlay_dispatch.tpl::pleme-lib.overlay.registry`):
fedramp-low, fedramp-moderate, fedramp-high, airgap-consumer,
airgap-registry-mirror, mirror, supplychain, fips, dod-il2, dod-il4,
dod-il5, dod-il6, hipaa, cmmc-l3.

**Each overlay defines 11 surfaces** as named templates following
`pleme-lib.overlay.<name>.<surface>`:
- `controls` (CSV of NIST/HIPAA/CMMC/DoD IDs)
- `requires` (CSV of cascaded overlay names)
- `validate` (template-time `fail()` invariants)
- `annotations`, `labels` (resource metadata)
- `policies` (workload-scope NetworkPolicies, etc.)
- `manifestData` (compliance-manifest ConfigMap fragment)
- `podEnv`, `imagePullSecrets` (pod spec contributions)
- `kyvernoPolicy`, `gatekeeperConstraint` (admission-time enforcement)

**The dispatch chain** (`_overlay_dispatch.tpl`):
- `pleme-lib.overlay.list` resolves declared overlays + transitive `requires` closure
- `pleme-lib.overlay.dispatchAll` aggregates a surface across all overlays
- `pleme-lib.overlay.dispatchDocuments` separates multi-document YAML output with `---`
- `pleme-lib.overlay.dispatchJoin` joins string surfaces with a separator (used by `controls`)
- `pleme-lib.overlay.synthesize` is the back-compat shim mapping legacy values → overlay list

**The proof** is in [`docs/COMPLIANCE-PROOF.md`](docs/COMPLIANCE-PROOF.md).
Mechanically: applying overlay set `{O₁..Oₙ}` either fails template
render with a clear control citation, or produces manifests satisfying
the union of `{O₁.controls .. Oₙ.controls}`. Adding a regime is one
new `_overlay_<name>.tpl` file plus one row in the registry plus tests
— see [`docs/OVERLAY-AUTHORING.md`](docs/OVERLAY-AUTHORING.md).

**Use-case primitives** (`/usecases/`) compose typed overlay sets +
workload defaults for recurring patterns. Operators compose via
`helm install -f usecases/<primitive>.yaml -f <overrides>.yaml`.
See [`docs/USECASES-PRIMITIVES.md`](docs/USECASES-PRIMITIVES.md) and
[`usecases/README.md`](usecases/README.md).

**Cluster-side admission policies** (`pleme-admission-policies` chart)
emit Kyverno ClusterPolicies + Gatekeeper Constraints from the same
overlay declaration as chart-time validators. Symmetric proof — drift
is structurally impossible. See
[`docs/ADMISSION-POLICIES.md`](docs/ADMISSION-POLICIES.md).

### Quick reference — compliance via overlays

```yaml
compliance:
  overlays: [fedramp-high]   # or [dod-il5], [hipaa, supplychain], [cmmc-l3], …
  enforce: true              # default true; set false for migration runs only
```

Selecting an overlay set mechanically:

- forces `seccompProfile=RuntimeDefault` and `automountServiceAccountToken=false` at moderate+
- requires `image.tag != "latest"` at moderate+; digest-pinned image at high
- emits default-deny + allow-DNS + allow-TLS-egress NetworkPolicies at moderate+
- emits mandatory `PodDisruptionBudget` and topology spread at high
- emits mandatory `ServiceMonitor` (AU-2, AU-12, SI-4)
- requires `attestation.enabled=true` at high (sekiban admission)
- requires a dedicated ServiceAccount at moderate+ (no `default`)
- forbids literal env values for secret-shaped variable names (IA-5)
- requires PVCs to use an encrypted-class storage class at high (SC-28)
- emits `compliance-manifest` ConfigMap describing covered overlays + controls
- adds `compliance.pleme.io/*` labels + annotations on every resource
- runs `fail()` validators that block non-compliant input at template render
- when `pleme-admission-policies` is installed, emits matching cluster-side
  Kyverno ClusterPolicies / Gatekeeper Constraints — symmetric proof

### Files (where to look for what)

```
charts/pleme-lib/templates/
  _overlay_dispatch.tpl          # registry, list resolver, closure expansion, dispatchers
  _overlay_fedramp.tpl           # fedramp-{low,moderate,high} overlays
  _overlay_airgap.tpl            # airgap-{consumer,registry-mirror} overlays
  _overlay_mirror.tpl            # mirror overlay (scheduled-sync)
  _overlay_supplychain.tpl       # supplychain overlay (SBOM/SLSA/cosign/scan)
  _overlay_fips.tpl              # fips overlay
  _overlay_dod.tpl               # dod-il2/4/5/6 overlays
  _overlay_hipaa.tpl             # hipaa overlay
  _overlay_cmmc.tpl              # cmmc-l3 overlay

  _compliance.tpl                # baseline / enabled / atLeast / controls / validate (entry points)
  _compliance_admission.tpl      # admissionPolicies aggregator
  _compliance_security.tpl       # pod / container securityContext (legacy helpers; overlays delegate)
  _compliance_image.tpl          # digest enforcement, pullPolicy
  _compliance_network.tpl        # default-deny + DNS + TLS egress
  _compliance_audit.tpl          # ServiceMonitor + audit annotations
  _compliance_availability.tpl   # PDB + topology spread + resources
  _compliance_attestation.tpl    # sekiban requirement at high
  _compliance_rbac.tpl           # dedicated ServiceAccount required
  _compliance_secrets.tpl        # secret-shaped env vars must use secretKeyRef
  _compliance_storage.tpl        # encrypted storage class allowlist
  _compliance_ingress.tpl        # ingress.tls required
  _compliance_egress.tpl         # generic egress.toService / egress.toUpstream primitives
  _compliance_authz.tpl          # RBAC Role/RoleBinding + no-wildcards validators
  _compliance_authn.tpl          # OIDC + mTLS + projected SA token primitives
  _compliance_airgap.tpl         # air-gap consumer + registry-mirror primitives
  _compliance_mirror.tpl         # generic scheduled-sync primitives
  _compliance_supplychain.tpl    # SBOM/SLSA/cosign/scan primitives
  _compliance_fips.tpl           # FIPS 140-3 primitives
  _compliance_il.tpl             # DoD CC SRG impact-level primitives
  _compliance_namespace.tpl      # PSS labels, namespace deny-all, ResourceQuota, LimitRange
  _compliance_manifest.tpl       # compliance-manifest ConfigMap
```

**The overlay layer is canonical**; the `_compliance_*.tpl` helpers are
implementation details that overlays delegate to. New compliance work
goes in overlay files, not new `_compliance_*.tpl` files.

**Proof:** `docs/COMPLIANCE-PROOF.md` is the proof that consumer charts using
only these primitives cannot produce a non-compliant K8s architecture at the
chart layer. The proof is mechanical:

- The negative test corpus (`tests/pleme-microservice/compliance_proof_negative_test.yaml`)
  enumerates every K8s-side FedRAMP-High invariant and demonstrates a
  violating value shape causes `helm template` to fail.
- The positive test corpus (`tests/pleme-microservice/compliance_proof_positive_test.yaml`)
  asserts every invariant holds in the rendered output of the canonical
  example values.
- The bare-fixture suite (`tests/_fixtures/pleme-lib-bare/compliance_lib_validators_test.yaml`)
  exercises validators that need empty-default inputs.

Pre-merge CI must run all three suites. A weakened validator surfaces as a
failed test, breaking the proof visibly.

**Trust boundary:** the proof covers the chart-render step. Cluster-side
guarantees (PSS admission, sekiban deployed, CNI NetworkPolicy enforcement,
encrypted storage class is actually encrypted, etc.) are documented in
`docs/COMPLIANCE-PROOF.md` § 2 and enforced by the cluster repos.

**Companion reference:**
- Cloud layer: `pangea-architectures/lib/pangea/architectures/generated/compliance/fedramp_high.rb`
- Compliance reporting: `kensa/src/mapping/fedramp.rs`
- Attestation chain: `tameshi/src/compliance/dimensions.rs`
- Admission gate: `sekiban/`

### `pleme-compliance` chart

Namespace-scope scaffolding chart. Apply once per namespace; every workload
deployed there inherits Pod Security Standard enforcement, default-deny
networking, and resource quotas matched to the baseline.

```bash
helm install regulated-ns oci://ghcr.io/pleme-io/charts/pleme-compliance \
  --namespace regulated --create-namespace \
  --set compliance.baseline=fedramp-high
```

## Integration with k8s repo

Charts are pushed to `oci://ghcr.io/pleme-io/charts`. FluxCD HelmReleases reference them:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
spec:
  chart:
    spec:
      chart: pleme-microservice
      version: "0.1.0"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
```

Environment-specific overrides use kustomize patches on the HelmRelease.
Secrets stay as SOPS-encrypted Secret YAMLs — never in Helm values.

## Adding a New Chart

1. Create `charts/<name>/` with `Chart.yaml` depending on `pleme-lib`
2. Add template files invoking `pleme-lib.*` named templates
3. Create `values.yaml` with sensible defaults
4. Add tests in `tests/<name>/`
5. Add example values in `examples/`
6. Add to `chartDefs` list in `flake.nix`

## pleme-lareira — home-services specialization

`pleme-lareira` is a thin library chart layered on `pleme-lib` for
homelab / family / household / single-author workloads (`lareira` is
Brazilian-Portuguese for *hearth* — the warm centre where the family
gathers). It does not replace `pleme-lib`; consumer charts depend on
both.

What `pleme-lareira` adds:

- **Default-off master toggle**: every consumer chart starts with
  `enabled: false`. Templates render empty by default; flip
  `enabled: true` in the FluxCD HelmRelease values to actually deploy.
  This keeps a 30-service homelab repo safe from accidental enable-all
  on merge to main.
- **`pleme-lareira.allResources`**: one helper that delegates to
  `pleme-lib` (Deployment, Service, ServiceAccount, NetworkPolicy,
  ServiceMonitor, PDB) plus `pleme-lareira` (Ingress, PVC, restic
  CronJob, alerts, breathability). Each consumer chart needs only
  `templates/all.yaml: {{ include "pleme-lareira.allResources" . }}`.
- **Authentik forward-auth** (`pleme-lareira.authentik.annotations`):
  nginx-ingress annotations that bounce unauthenticated requests
  through the Authentik embedded outpost.
- **Cloudflare Tunnel marker** (`pleme-lareira.cloudflared.serviceAnnotations`):
  Service annotations the host-side cloudflared reconciler reads to
  populate tunnel ingress entries. The cloudflared daemon stays on the
  host (NixOS module) for ownership reasons.
- **ZFS-aware PVC** (`pleme-lareira.pvc`): local-path-provisioner PVC
  with optional node pinning + ZFS dataset hint surfaced as labels for
  alert routing.
- **Restic backup CronJob** (`pleme-lareira.restic.cronjob`): mounts the
  PVC read-only, runs `restic backup` + `restic forget --prune` on a
  schedule. Optional weekly verify CronJob.
- **Common alerts** (`pleme-lareira.alerts.common`): baseline
  PrometheusRule covering PodDown, PodRestarting, PodOOMKilled,
  PvcUsedHigh (when persistence enabled), ResticBackupStale +
  ResticBackupFailing (when backup enabled).
- **Cron-driven breathability** (`pleme-lareira.breathability.cron`):
  KEDA `ScaledObject` with cron trigger — wake during the day, sleep
  overnight. Composes with `pleme-lib`'s NATS-driven trigger.

### Consumer chart skeleton

```yaml
# Chart.yaml
dependencies:
  - { name: pleme-lib,      version: "~0.5.0", repository: "file://../pleme-lib" }
  - { name: pleme-lareira,  version: "~0.1.0", repository: "file://../pleme-lareira" }
```

```yaml
# templates/all.yaml
{{- include "pleme-lareira.allResources" . }}
```

```yaml
# values.yaml — minimum
enabled: false
image: { repository: …, tag: … }
ports: [{ name: http, containerPort: …, protocol: TCP }]
service:
  type: ClusterIP
  ports: [{ name: http, port: …, targetPort: http, protocol: TCP }]
serviceAccount: { create: true }
persistence: { enabled: false, size: 10Gi, mountPath: /data, zfsDataset: pool/data }
ingress: { enabled: false, className: nginx, hosts: [...] }
backup:
  enabled: false
  image: { repository: restic/restic, tag: "0.18.0", pullPolicy: IfNotPresent }
  resources: { requests: { cpu: 50m, memory: 64Mi }, limits: { cpu: 500m, memory: 256Mi } }
```

### Existing pleme-lareira-based charts

| Chart | Service | Default port | Dataset |
|---|---|---|---|
| `lareira-vaultwarden` | Bitwarden-compatible password manager | 80 | pool/data |
| `lareira-immich` | Photo / video library (Google Photos alt) | 2283 | pool/photos |
| `lareira-jellyfin` | Media server | 8096 | pool/data + hostPath /srv/pool/media |
| `lareira-paperless` | OCR document archive (Paperless-ngx) | 8000 | pool/data |
| `lareira-adguard` | Network DNS ad-blocker (AdGuard Home) | 53/80 | pool/data |
| `lareira-home-assistant` | Smart-home automation | 8123 | pool/data |
| `lareira-ntfy` | Push-notification server | 80 | pool/data |
| `lareira-forgejo` | Self-hosted git forge | 3000/22 | pool/data |
| `lareira-hedgedoc` | Real-time collaborative markdown | 3000 | pool/data |
| `lareira-listmonk` | Newsletter / mailing-list | 9000 | pool/data |

Reference cluster: [`pleme-io/k8s/clusters/rio`](../k8s/clusters/rio).

### Testing

`helm lint` clean for every chart. `helm template` against default
values produces empty output (default-off). The `pleme-lareira-canary`
chart exercises every helper at once and is used to validate library
edits.

```bash
# Lint everything
nix run .#lint

# Smoke test default-off behaviour
for c in lareira-*; do
  out=$(helm template smoke charts/$c)
  [[ -z "$out" ]] || echo "FAIL: $c rendered with default values"
done

# Validate canary fully renders
helm template canary charts/pleme-lareira-canary \
  -f charts/pleme-lareira-canary/values-all-on.yaml | grep -E "^kind:" | sort | uniq -c
```
