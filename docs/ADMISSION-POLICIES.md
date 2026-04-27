# Admission policy emission — symmetric proof

> Companion: [`COMPLIANCE-OVERLAYS-DESIGN.md`](./COMPLIANCE-OVERLAYS-DESIGN.md),
> [`COMPLIANCE-PROOF.md`](./COMPLIANCE-PROOF.md).

The compliance proof has two halves:

1. **Chart-time validation** (every helmworks chart): consumer values
   that violate a compliance invariant cause `helm template` to `fail()`.
2. **Cluster-side admission** (`pleme-admission-policies`): every pod
   admitted by the kube-apiserver — helmworks-rendered or not — is
   re-validated against the same invariants by Kyverno + Gatekeeper.

Both halves come from the **same overlay declaration** in `pleme-lib`'s
overlay registry. Drift is structurally impossible.

## How it works

Each registered overlay defines two surfaces:

```
pleme-lib.overlay.<name>.kyvernoPolicy       — Kyverno ClusterPolicy YAML
pleme-lib.overlay.<name>.gatekeeperConstraint — Gatekeeper Constraint YAML
```

The `pleme-admission-policies` chart's single template walks the resolved
overlay list and emits the union of every overlay's
`kyvernoPolicy` + `gatekeeperConstraint` surfaces:

```yaml
# charts/pleme-admission-policies/templates/policies.yaml
{{- include "pleme-lib.compliance.validate" . -}}
{{ include "pleme-lib.compliance.admissionPolicies" . }}
```

Operators install once per cluster declaring the overlay set the cluster
should enforce:

```bash
helm install pleme-policies oci://ghcr.io/pleme-io/charts/pleme-admission-policies \
  --namespace kyverno-system \
  --set 'compliance.overlays={fedramp-high,airgap-consumer,supplychain,fips,dod-il5,hipaa}'
```

The cluster receives a stack of `ClusterPolicy` (Kyverno) and
`Constraint` (Gatekeeper) resources, each scoped to validate at
admission time. A non-helmworks chart that violates an invariant is
rejected at admission — the invariant is enforced at both ends.

## What each overlay enforces

| Overlay | Kyverno policy contents |
|---|---|
| `fedramp-low` | (none — labels-only overlay) |
| `fedramp-moderate` | Forbid `privileged`, `allowPrivilegeEscalation`; require `readOnlyRootFilesystem`, drop ALL caps; forbid host namespaces; forbid `:latest` tag |
| `fedramp-high` | (cascade through fedramp-moderate) + require digest-pinned image; require `runAsNonRoot`; forbid `runAsUser=0` |
| `airgap-consumer` / `airgap-registry-mirror` | (none — egress NetworkPolicy is in `policies` surface) |
| `supplychain` | Kyverno `verifyImages` rule with cosign public key |
| `fips` | Require image base from FIPS-mode allowlist (registry1.dso.mil/, cgr.dev/chainguard/, registry.access.redhat.com/ubi*) |
| `dod-il2/4/5/6` | (none — cascade through fedramp + airgap + supplychain + fips brings the substantive rules) |
| `hipaa` | Require `audit.pleme.io/retention-days` annotation (≥2190 days; HIPAA §164.316(b)(2)(i)) |
| `cmmc-l3` | (cascade) |

## Symmetric proof

For every NIST 800-53 / HIPAA / CMMC / DoD control covered by an
overlay, **the same overlay file** declares:

- the chart-time validator that prevents non-compliant values from
  rendering
- the admission-time policy that prevents non-compliant manifests from
  being admitted

This is the structural property the design depends on: chart bytes
that pass validation are the same bytes that pass admission, and
non-helmworks bytes get caught at admission. There is no path to
deploy non-compliant workloads in a cluster running this admission
chart at the declared overlay set.

## Operational model

```
┌────────────────────┐                       ┌──────────────────────┐
│   Workload chart   │                       │  pleme-admission-    │
│   declares overlay │                       │  policies installed  │
│   set in values    │                       │  at cluster level    │
└──────────┬─────────┘                       └──────────┬───────────┘
           │                                            │
           │  helm template → manifests                 │  emits N
           │  +  validators reject non-compliant        │  ClusterPolicies
           │     inputs (chart-time enforcement)        │  + Constraints
           ▼                                            ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Cluster admission webhooks                        │
│     Kyverno + Gatekeeper validate every Pod manifest at admission     │
│     against the SAME overlay declarations the chart was rendered      │
│     against. Drift = impossible.                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Cluster prerequisites

The admission-policies chart is purely the *policy authors*. The cluster
must have:

- **Kyverno** installed (default Helm chart from `kyverno/kyverno`)
  for the ClusterPolicies to take effect
- **OPA Gatekeeper** installed (default Helm chart from
  `open-policy-agent/gatekeeper`) for the Constraints to take effect

If only one is installed, the other surface's emissions are inert
(the kind doesn't exist in the API). This is intentional — the chart
emits both so a cluster with only Kyverno OR only Gatekeeper still
gets the relevant half.

## Cluster-side configuration

The admission policies cascade through the overlay registry:

```yaml
# charts/pleme-admission-policies/values.yaml
compliance:
  overlays:
    - fedramp-high
    - airgap-consumer
    - supplychain
    - fips
  # Closure pulls in fedramp-moderate. If operator declares dod-il5,
  # the cascade auto-includes fedramp-high + airgap-consumer +
  # supplychain + fips.
  supplychain:
    cosign:
      publicKey: ""   # injected via ExternalSecret in production
```

Operators inject the cosign public key for the supplychain overlay's
`verifyImages` rule via External Secrets Operator / Sealed Secrets /
SOPS. The chart's compliance validators catch missing required values
at install time.

## Adding a new admission rule

Adding a new admission-time check is a **per-overlay** change:

1. Edit the relevant `_overlay_<regime>.tpl`.
2. Extend the `pleme-lib.overlay.<regime>.kyvernoPolicy` template to
   add a new `rule` to the emitted `ClusterPolicy`.
3. Add a chart-time validator in
   `_compliance_<concern>.tpl::<concern>.validate` that asserts the
   same invariant on values.
4. Add a negative test in
   `tests/pleme-microservice/compliance_proof_negative_test.yaml`
   asserting the chart-time validator fires.
5. Add a positive smoke test in
   `tests/pleme-admission-policies/admission_policies_test.yaml`
   asserting the admission-time policy renders.
6. Update the COMPLIANCE-PROOF.md control surface table.

The principle: **chart-time and admission-time invariants are declared
together and tested together**. A new control gets both halves of the
proof in one PR.

## Future enhancements

- **Sigstore Policy Controller** as a third surface (alongside Kyverno
  + Gatekeeper) — first-class for image-signature verification with
  TUF trust roots.
- **Falco rules** as a fourth surface — runtime-detection rules
  emitted from each overlay (e.g. supplychain overlay emits the
  drift-detected rule).
- **OSCAL component-definition snippets** — every overlay's controls
  list flows into auto-generated OSCAL evidence packages for 3PAO
  assessors via kensa.
