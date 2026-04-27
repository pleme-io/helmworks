# helmworks

Reusable Helm chart library for pleme-io services with **provable
compliance overlays** — a single-declaration surface for FedRAMP /
FIPS / DoD-IL2…IL6 / HIPAA / CMMC / supply-chain posture that
mechanically composes through every chart in the fleet.

## At-a-glance

```yaml
# A regulated workload's entire compliance posture is one declaration:
compliance:
  overlays: [dod-il5]   # cascades fedramp-high, airgap-consumer, supplychain, fips
```

The chart-time validators reject non-compliant inputs before render. The
companion `pleme-admission-policies` chart deploys cluster-side Kyverno
+ Gatekeeper policies emitted from the *same* overlay declaration. Any
non-helmworks chart that violates an invariant is also rejected at
admission. Drift is structurally impossible.

## Charts

### Library + scaffolding

| Chart | Purpose |
|-------|---------|
| `pleme-lib` | Shared library: overlay registry, dispatch, validators, helpers. **Authoritative compliance surface.** |
| `pleme-compliance` | Namespace-scope scaffolding (PSS labels, default-deny NetworkPolicy, ResourceQuota, LimitRange) |
| `pleme-admission-policies` | Cluster-side Kyverno ClusterPolicies + Gatekeeper Constraints emitted from the declared overlay set |

### Air-gap registry

| Chart | Purpose |
|-------|---------|
| `pleme-zot` | Cluster-local Zot OCI registry, registry-mirror role, encrypted PVC, OIDC, cosign verification |
| `pleme-image-sync` | CronJob that mirrors upstream registries into Zot (skopeo + cosign verify) |

### Workload patterns

| Chart | Use for |
|-------|---------|
| `pleme-microservice` | HTTP service (REST/GraphQL/gRPC) |
| `pleme-worker` | Background worker (no Service) |
| `pleme-web` | Frontend + BFF |
| `pleme-cronjob` | Scheduled jobs |
| `pleme-statefulset` | Stateful workloads |
| `pleme-database` / `pleme-cache` / `pleme-storage-elastic` | Data services |
| `pleme-migration` | Shinka DatabaseMigration CRD |
| `pleme-operator` / `pleme-bootstrap` / `pleme-namespace` | K8s operators / cluster bootstrap / namespace provisioning |
| `pleme-gpu-workload` / `pleme-wasm` | Specialized runtimes |
| `pleme-arc-controller` | GitHub Actions Runner Controller — cluster install + GitHub App ExternalSecret |
| `pleme-arc-runner-pool` | GitHub Actions runner pool — IRSA SA + namespace RBAC + dedicated Karpenter NodePool + AutoscalingRunnerSet |

### Application charts

`hanabi`, `shinka`, `kenshi`, `arachne`, `sekiban`, `headscale`, `iac-forge`,
30+ `lareira-*` (homelab services), and others — see `charts/`.

## Compliance overlays

The canonical surface is `compliance.overlays: [...]` — a list of
typed overlays from the registry in `pleme-lib`'s
`_overlay_dispatch.tpl`. Each overlay declares: control coverage,
`requires` (transitive overlays), validators, annotations,
manifestData, podEnv, image-pull secrets, Kyverno policies, Gatekeeper
constraints.

**Registered overlays (`pleme-lib` 0.10.0):**

| Overlay | Source | What it adds |
|---|---|---|
| `fedramp-low` | NIST 800-53 Rev 5 Low | Labels + manifest only |
| `fedramp-moderate` | NIST 800-53 Rev 5 Moderate / FedRAMP | Hardened security context, NetworkPolicy, RBAC, audit, OIDC ingress, ImagePullPolicy=Always, no-`latest`-tag |
| `fedramp-high` | NIST 800-53 Rev 5 High / FedRAMP-High | Adds: digest-pinned image, encrypted PVC, attestation, mandatory PDB + topology spread, mTLS at high |
| `airgap-consumer` | DoD CC SRG SC-7(11)/(12) | Workload egresses ONLY to cluster-local registry |
| `airgap-registry-mirror` | Same | Workload egresses to a curated upstream allowlist (Zot in pull mode, image-sync) |
| `mirror` | NIST AU/IA/SI/SR | Generic scheduled-sync workload (cosign verify, upstream creds) |
| `supplychain` | EO 14028 / NIST 800-218 SSDF / IronBank / Sigstore / SLSA 1.0 | Mandatory SBOM (CycloneDX 1.4+ or SPDX 2.3), cosign signature, SLSA L≥2, scan attestation, CVE thresholds (Critical=0, High=0) |
| `fips` | FIPS 140-3 / NIST CMVP | FIPS-mode env vars (Go-boringcrypto / OpenSSL-3-FIPS / BC-FIPS / AWS-LC / Node / Python), TLS 1.2/1.3, IronBank/Chainguard image base |
| `dod-il2` / `dod-il4` / `dod-il5` / `dod-il6` | DoD CC SRG v1r4 | Cumulative DoD impact-level overlays (cascade FedRAMP + airgap + FIPS + IronBank as required) |
| `hipaa` | HIPAA Security Rule §164.308/310/312 | Encryption at rest mandatory, 6-year audit retention, ePHI annotations |
| `cmmc-l3` | CMMC v2.0 L3 / NIST 800-171 R2 + 800-172 | Cosign signature mandatory, FedRAMP-High + DoD-IL4 + supplychain cascade |

Adding a new regime (PCI-DSS, NIS2, BSI C5, ISO 27001, SOC 2 T2) is **one
new `_overlay_<name>.tpl` file + one row in
`pleme-lib.overlay.registry`**. No central edits.

## Use-case primitives

`/usecases/` is a library of typed values fragments that compose the
right overlay set + workload defaults for a recurring use-case.
Operators stack them via Helm's standard multi-`-f`:

```bash
helm install my-service oci://ghcr.io/pleme-io/charts/pleme-microservice \
  -f usecases/dod-il5-microservice.yaml \
  -f my-service-overrides.yaml
```

Library at `pleme-lib` 0.10.0:
- `fedramp-high-microservice.yaml` — civilian-agency regulated SaaS
- `dod-il5-microservice.yaml` — DoD CUI national-security workload
- `hipaa-microservice.yaml` — ePHI-handling SaaS
- `cmmc-l3-microservice.yaml` — DoD contractor CUI
- `regulated-microservice.yaml` — fedramp-moderate light

Adding a use-case is **one new YAML file** in `usecases/`. See
`usecases/README.md`.

## Tests + proof

**156 compliance tests across 12 suites at `pleme-lib` 0.10.0.**

The proof is in [`docs/COMPLIANCE-PROOF.md`](docs/COMPLIANCE-PROOF.md):
applying any overlay set to a workload chart either (a) fails template
render with a clear error citing the violated control, or (b) produces
manifests that satisfy the union of all applied overlays' controls.

CI runs:
```bash
nix run .#lint                                                     # all charts
helm unittest charts/pleme-microservice                            # legacy + compliance suites
helm unittest charts/pleme-compliance -f '../../tests/pleme-compliance/namespace_test.yaml'
helm unittest charts/pleme-zot -f '../../tests/pleme-zot/zot_compliance_test.yaml'
helm unittest charts/pleme-image-sync -f '../../tests/pleme-image-sync/image_sync_test.yaml'
helm unittest charts/pleme-admission-policies -f '../../tests/pleme-admission-policies/admission_policies_test.yaml'
helm unittest charts/pleme-microservice -f '../../tests/usecases/usecases_test.yaml'
helm unittest tests/_fixtures/pleme-lib-bare -f 'compliance_lib_validators_test.yaml'
```

## Documentation

| Doc | Topic |
|---|---|
| [`docs/COMPLIANCE-PROOF.md`](docs/COMPLIANCE-PROOF.md) | The mechanical proof: per-control surface mapping, validator tests, trust boundary |
| [`docs/COMPLIANCE-OVERLAYS-DESIGN.md`](docs/COMPLIANCE-OVERLAYS-DESIGN.md) | Design specification for the overlay registry pattern |
| [`docs/AIRGAP-PATTERN.md`](docs/AIRGAP-PATTERN.md) | Operational walkthrough: pleme-zot + pleme-image-sync + air-gap consumer |
| [`docs/AIRGAP-RESEARCH.md`](docs/AIRGAP-RESEARCH.md) | Research brief: NSA Hardening / DISA STIG / DoD IL / IronBank / Sigstore / SLSA / FIPS / OPA-Kyverno / Falco |
| [`docs/USECASES-PRIMITIVES.md`](docs/USECASES-PRIMITIVES.md) | Pattern doc for the `usecases/` library |
| [`docs/ADMISSION-POLICIES.md`](docs/ADMISSION-POLICIES.md) | Pattern doc for cluster-side admission emission |
| [`docs/OVERLAY-AUTHORING.md`](docs/OVERLAY-AUTHORING.md) | How to add a new compliance regime (recipe) |
| [`usecases/README.md`](usecases/README.md) | Use-case primitive library index + extension recipe |
| [`CLAUDE.md`](CLAUDE.md) | Canonical agent-facing context for working in this repo |

## Nix Apps

```bash
nix run .#lint                              # lint all charts
nix run .#lint:pleme-microservice           # lint a specific chart
nix run .#package                           # package all charts
nix run .#push                              # push all to OCI registry
nix run .#release                           # full lifecycle: lint + package + push
nix run .#template -- pleme-microservice examples/releases.yaml   # render
nix develop                                 # shell with helm + kubectl + yq
```

Registry: `oci://ghcr.io/pleme-io/charts`

## License

MIT
