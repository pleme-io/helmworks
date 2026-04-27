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

## Chart Architecture

**pleme-lib** is a library chart providing named templates:
- `pleme-lib.deployment` — standard Deployment
- `pleme-lib.service` — ClusterIP Service
- `pleme-lib.serviceaccount` — ServiceAccount (IRSA-ready via `serviceAccount.annotations`)
- `pleme-lib.servicemonitor` — Prometheus ServiceMonitor
- `pleme-lib.networkpolicy` — deny-all + allow-dns + allow-prometheus
- `pleme-lib.pdb` — PodDisruptionBudget
- `pleme-lib.hpa` — HorizontalPodAutoscaler
- `pleme-lib.karpenterNodePool` / `pleme-lib.karpenterEC2NodeClass` — Karpenter primitives, iterate values maps for multi-pool charts (added v0.6.0)
- `pleme-lib.namespacedRBAC` — namespace-scoped Role + RoleBinding pairs from a values map (added v0.6.0)
- `pleme-lib.externalSecret` — External Secrets Operator ExternalSecret resources from a values map; defaults to `cluster-secret-store` (override per entry) (added v0.6.0)

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

## Compliance Primitives (FedRAMP Low / Moderate / High)

`pleme-lib` ≥ 0.6.0 ships compliance primitives that encode the K8s-side
mapping of NIST 800-53 controls. A consumer chart selects a baseline:

```yaml
compliance:
  baseline: fedramp-high   # or fedramp-moderate / fedramp-low / ""
  enforce: true
```

Selecting a baseline mechanically:

- forces `seccompProfile=RuntimeDefault` and `automountServiceAccountToken=false` at moderate+
- requires `image.tag != "latest"` at moderate+; requires digest-pinned image at high
- emits a default-deny + allow-DNS + allow-TLS-egress NetworkPolicy trio at moderate+
- emits a mandatory `PodDisruptionBudget` and topology spread at high
- emits a mandatory `ServiceMonitor` (AU-2, AU-12, SI-4)
- requires `attestation.enabled=true` at high (sekiban admission)
- requires a dedicated ServiceAccount at moderate+ (no `default`)
- forbids literal env values for secret-shaped variable names (IA-5)
- requires PVCs to use an encrypted-class storage class at high (SC-28)
- emits a `compliance-manifest` ConfigMap describing controls covered
- adds `compliance.pleme.io/*` labels and annotations to every resource
- runs `fail()` validators that block non-compliant input at template render

Templates:
- `_compliance.tpl` — entry points (`baseline`, `labels`, `annotations`, `validate`)
- `_compliance_security.tpl` — pod / container securityContext, host* forbidden
- `_compliance_image.tpl` — digest enforcement, pullPolicy
- `_compliance_network.tpl` — default-deny + DNS + TLS egress
- `_compliance_audit.tpl` — ServiceMonitor + audit annotations
- `_compliance_availability.tpl` — PDB + topology spread + resources
- `_compliance_attestation.tpl` — sekiban requirement at high
- `_compliance_rbac.tpl` — dedicated ServiceAccount required
- `_compliance_secrets.tpl` — secret-shaped env vars must use secretKeyRef
- `_compliance_storage.tpl` — encrypted storage class allowlist (high)
- `_compliance_ingress.tpl` — ingress.tls required when ingress.enabled
- `_compliance_namespace.tpl` — PSS labels, namespace deny-all, ResourceQuota, LimitRange
- `_compliance_manifest.tpl` — ConfigMap describing claimed compliance posture

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
