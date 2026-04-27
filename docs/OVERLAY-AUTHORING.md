# Authoring a new compliance overlay

> Companion: [`COMPLIANCE-OVERLAYS-DESIGN.md`](./COMPLIANCE-OVERLAYS-DESIGN.md),
> [`COMPLIANCE-PROOF.md`](./COMPLIANCE-PROOF.md),
> [`ADMISSION-POLICIES.md`](./ADMISSION-POLICIES.md).

Adding a new compliance regime (PCI-DSS, NIS2, BSI C5, ISO 27001,
SOC 2 T2, NIST 800-171 generic, …) is **one new file** in
`charts/pleme-lib/templates/_overlay_<name>.tpl` plus one row in the
overlay registry plus one smoke test. This document is the recipe.

## The 11 surfaces

Every overlay defines 11 named templates following the pattern
`pleme-lib.overlay.<name>.<surface>`. If a surface is irrelevant, the
overlay still defines it as empty — the dispatcher walks all 11
unconditionally.

| Surface | Returns | Used by |
|---|---|---|
| `controls` | comma-separated control IDs | `compliance.controls` aggregator → labels + annotations + manifest |
| `requires` | comma-separated overlay names this overlay needs | `overlay.list` closure expansion |
| `validate` | `fail()` invariants | `compliance.validate` on every chart's render |
| `annotations` | metadata.annotations key/value lines | `resourceAnnotations` on every K8s object |
| `labels` | metadata.labels key/value lines | (currently unused by the standard helpers; reserved) |
| `policies` | full K8s objects (NetworkPolicy, etc.) separated by `---` | `_networkpolicy.tpl` |
| `manifestData` | data fragment for `compliance-manifest` ConfigMap | `_compliance_manifest.tpl` |
| `podEnv` | env list entries | `_deployment.tpl`, `_statefulset.tpl`, `_cronjob.tpl` |
| `imagePullSecrets` | pullSecret name list | same |
| `kyvernoPolicy` | Kyverno `ClusterPolicy` YAML | `_compliance_admission.tpl` (consumed by `pleme-admission-policies` chart) |
| `gatekeeperConstraint` | Gatekeeper `Constraint` YAML | same |

## Recipe (worked example: adding `pci-dss`)

### 1. Identify the regime's K8s-mappable controls

Read the regime spec. Identify which control families map to K8s
workloads (most do — encryption, access, audit, network). Cross-check
against the [`AIRGAP-RESEARCH.md`](./AIRGAP-RESEARCH.md) brief for
mappings to NIST 800-53 (the substrate most regimes overlay).

For PCI-DSS v4.0, the relevant K8s mappings:
- §1 Network security — `airgap-consumer` covers most
- §2 Secure configurations — fedramp-moderate covers (PSS=restricted)
- §3 Stored data protection — needs encrypted storage class
- §4 Strong cryptography — fedramp-moderate (TLS) + fips
- §6 Develop and maintain secure systems — supplychain (SBOM, scan)
- §8 Identify and authenticate — fedramp-moderate (OIDC)
- §10 Log and monitor — fedramp-moderate (ServiceMonitor)

So PCI-DSS `requires` = `[fedramp-moderate, supplychain]`. The PCI-DSS
overlay itself adds card-data-specific controls.

### 2. Create the overlay file

```gotemplate
{{/*
Overlay: pci-dss
Source: PCI DSS v4.0 (March 2022) — Payment Card Industry Data Security Standard
*/}}

{{- define "pleme-lib.overlay.pci-dss.requires" -}}fedramp-moderate,supplychain{{- end }}

{{- define "pleme-lib.overlay.pci-dss.controls" -}}
PCI-DSS-1.2,PCI-DSS-2.2,PCI-DSS-3.5,PCI-DSS-3.6,PCI-DSS-4.2,PCI-DSS-6.3,PCI-DSS-8.3,PCI-DSS-10.4
{{- end }}

{{- define "pleme-lib.overlay.pci-dss.validate" -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- if eq $isWorkload "true" -}}
  {{- /* PCI-DSS §3.5 Cardholder data must be encrypted at rest */ -}}
  {{- $persistence := .Values.persistence | default dict -}}
  {{- if eq (toString $persistence.enabled) "true" -}}
    {{- $sc := $persistence.storageClass | default $persistence.storageClassName | default "" | toString -}}
    {{- if eq $sc "" -}}
      {{- fail (printf "compliance: pci-dss requires persistence.storageClass to be set to an encrypted class (PCI-DSS §3.5)") -}}
    {{- end -}}
  {{- end -}}
  {{- /* PCI-DSS §10.5.5 Audit log retention >= 1 year */ -}}
  {{- $audit := (.Values.compliance).audit | default dict -}}
  {{- $retention := $audit.retentionDays | default 365 | int -}}
  {{- if lt $retention 365 -}}
    {{- fail (printf "compliance: pci-dss requires audit retention >= 365 days (PCI-DSS §10.5.5); got %d" $retention) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.pci-dss.annotations" -}}
compliance.pleme.io/overlay-pci-dss: "true"
pleme.io/pci-dss-version: "v4.0"
{{ end }}

{{- define "pleme-lib.overlay.pci-dss.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.pci-dss.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.pci-dss.manifestData" -}}
overlay-pci-dss: "true"
pci-dss-version: "v4.0"
{{ end }}

{{- define "pleme-lib.overlay.pci-dss.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.pci-dss.imagePullSecrets" -}}{{- end }}

{{/* Kyverno admission-time check: enforce the same persistence
     invariant at admission. Symmetric proof. */}}
{{- define "pleme-lib.overlay.pci-dss.kyvernoPolicy" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pleme-overlay-pci-dss
  annotations:
    pleme.io/overlay: pci-dss
    pleme.io/controls: "PCI-DSS-3.5,PCI-DSS-10.5.5"
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: pci-dss-pvc-encrypted-class
      match:
        any:
          - resources:
              kinds: ["PersistentVolumeClaim"]
              selector:
                matchLabels:
                  compliance.pleme.io/overlay-pci-dss: "true"
      validate:
        message: "PCI-DSS requires PVCs to use an encrypted storage class (§3.5)"
        pattern:
          spec:
            storageClassName: "*encrypted*"
{{ end }}
{{- define "pleme-lib.overlay.pci-dss.gatekeeperConstraint" -}}{{- end }}
```

### 3. Register in the overlay registry

Edit `_overlay_dispatch.tpl` and append to the registry list:

```gotemplate
{{- define "pleme-lib.overlay.registry" -}}
fedramp-low,fedramp-moderate,fedramp-high,airgap-consumer,airgap-registry-mirror,mirror,supplychain,fips,dod-il2,dod-il4,dod-il5,dod-il6,hipaa,cmmc-l3,pci-dss
{{- end }}
```

### 4. Add a smoke test

Append to
`tests/pleme-microservice/compliance_overlay_smoke_test.yaml`:

```yaml
  - it: "[smoke] pci-dss — PCI DSS v4.0"
    set:
      <<: *defaults
      compliance.overlays: ["pci-dss"]
      compliance.audit.retentionDays: 365
      compliance.supplychain.enabled: true
      compliance.supplychain.sbom.digest: "sha256:abc"
      compliance.supplychain.sbom.format: cyclonedx-1.5
      compliance.supplychain.cosign.signatureRef: "oci://x"
      compliance.supplychain.scan.resultDigest: "sha256:def"
      compliance.authn.oidc.provider: authentik
      ingress.tls:
        - hosts: ["example.com"]
          secretName: example-tls
      ingress.hosts:
        - host: example.com
    asserts:
      - matchRegex:
          path: data.overlays
          pattern: "pci-dss"
      - equal:
          path: data.overlay-pci-dss
          value: "true"
```

### 5. Add negative tests for the validators

Append to
`tests/pleme-microservice/compliance_proof_negative_test.yaml`:

```yaml
  - it: "[PCI-DSS-§3.5] rejects unencrypted PVC under pci-dss overlay"
    set:
      <<: *defaults
      compliance.overlays: ["pci-dss"]
      persistence.enabled: true
      persistence.storageClass: standard
    asserts:
      - failedTemplate:
          errorPattern: "pci-dss requires persistence.storageClass.*encrypted"
```

### 6. Add a use-case primitive (optional but recommended)

Create `usecases/pci-dss-payment-gateway.yaml`:

```yaml
compliance:
  overlays:
    - pci-dss
  enforce: true
  audit:
    retentionDays: 365
  supplychain:
    enabled: true
    sbom: { format: cyclonedx-1.5 }
    slsa: { level: 2 }
  authn:
    oidc: { provider: authentik }
    istio: { mtls: { required: true } }
# workload defaults
replicaCount: 3
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits: { memory: 512Mi }
persistence:
  enabled: true
  storageClass: encrypted
  size: 50Gi
  mountPath: /data
# ...
```

Add a smoke test in `tests/usecases/usecases_test.yaml`.

### 7. Update the README + COMPLIANCE-PROOF.md

- README.md: add a row to the registered overlays table.
- COMPLIANCE-PROOF.md: add a §3.x section enumerating the controls
  and pointing to the negative + positive tests.

### 8. Done

The new regime is now available to every workload chart in the fleet
via `compliance.overlays: [pci-dss]` or
`compliance.overlays: [pci-dss-payment-gateway]` (after step 6) or
`-f usecases/pci-dss-payment-gateway.yaml` (canonical).

Cluster admission policies update by re-installing
`pleme-admission-policies` with the updated overlay set.

## Naming conventions

- Overlay names are lowercase, hyphenated: `pci-dss`, `nis2`,
  `bsi-c5`, `iso-27001`, `soc-2-type-ii`.
- Cumulative levels become separate overlays: `dod-il2`, `dod-il4`,
  `dod-il5`, `dod-il6` (not a single `dod` overlay with a level field).
- Use-case primitives are `<regime>-<workload-shape>`:
  `pci-dss-payment-gateway`, `hipaa-database`, `nis2-eu-microservice`.

## Conventions on what an overlay should and shouldn't enforce

**Should:**
- Enforce invariants the regime *requires by spec*. Cite the section.
- Compose proven overlays via `requires` for shared substrate (most
  regimes share NIST-800-53 fedramp-moderate as a base).
- Emit both chart-time validators AND admission-time policies for
  every enforced invariant — symmetric proof.

**Shouldn't:**
- Add invariants the regime doesn't actually require. Compliance scope
  creep undermines the proof.
- Duplicate invariants from a `required` overlay. The cascade handles it.
- Embed customer-specific or fleet-specific values. Those go in
  use-case primitives, not the overlay.

## Anti-pattern: the kitchen-sink overlay

If you find yourself building one giant `mega-compliance` overlay with
20 fields and 50 validators, you're conflating regime + use-case +
fleet config. Split:
- The **regime** parts go in their own overlay file (composes via requires).
- The **use-case** parts go in `/usecases/`.
- The **fleet config** goes in the consumer chart's values.

The mechanical proof depends on overlays being small and individually
proven. Stay disciplined.
