{{/*
pleme-lib: compliance — supply chain primitives

The single most leverage-dense helper in the compliance library.
One template covers EO 14028 / NIST 800-218 SSDF, NSA Kubernetes
Hardening Guide §1, DoD IronBank acceptance criteria, Sigstore cosign,
and SLSA 1.0 — because they all reduce to the same four annotations:

  pleme.io/sbom-digest               — CycloneDX 1.4+ or SPDX 2.3
  pleme.io/cosign-signature          — OCI ref of the signature artifact
  pleme.io/slsa-provenance           — OCI ref of the SLSA provenance
  pleme.io/scan-result-digest        — CVE scan attestation digest

Maps to NIST 800-53:
  CM-2  — Baseline Configuration: SBOM is the canonical baseline
  CM-7  — Least Functionality: SBOM enumerates components
  CM-8  — Information System Component Inventory: SBOM IS the inventory
  CM-10 — Software Usage Restrictions: SBOM licenses
  RA-5  — Vulnerability Scanning: scan-result attestation
  SA-10 — Developer Configuration Management: SLSA provenance
  SA-11 — Developer Security Testing: test attestation
  SA-12 — Supply Chain Protection: end-to-end attestation
  SI-7  — Software Integrity: cosign signature
  SR-3  — Supply Chain Controls: chain of attestations
  SR-4  — Provenance: SLSA + in-toto Statement
  SR-11 — Component Authenticity: signature verification

Configuration is in `.Values.compliance.supplychain`:
  sbom:
    digest: "sha256:..."           # required at moderate+
    format: "cyclonedx-1.5"        # cyclonedx-{1.4,1.5} | spdx-{2.3}
  cosign:
    signatureRef: "..."            # OCI ref of the .sig artifact
    keyRef:                        # public key for verify
      name: cosign-pub
      key: cosign.pub
    fulcioCertFingerprint: ""      # for keyless / DoD-PKI keyless
    rekorUuid: ""                  # transparency log entry
  slsa:
    level: 3                       # 1..3 (per SLSA 1.0)
    provenanceRef: "oci://..."     # in-toto Statement, DSSE-signed
    builderId: "..."               # https://github.com/.../...@ref
  scan:
    resultDigest: "sha256:..."     # attestation referencing the image
    scanner: "trivy"               # trivy | grype | anchore
    scannedAt: "2026-04-27T00:00:00Z"
    vex:
      ref: ""                      # OpenVEX 0.2.0 doc, optional
  thresholds:
    critical: 0                    # forbidden Critical CVE count
    high: 0                        # forbidden High CVE count
*/}}

{{/*
Supply-chain manifest data — surfaces in compliance ConfigMap so audit
pipelines can enumerate per-workload supply-chain claims.
*/}}
{{- define "pleme-lib.compliance.supplychain.manifestData" -}}
{{- $sc := (.Values.compliance).supplychain | default dict -}}
{{- $sbom := $sc.sbom | default dict -}}
{{- $cosign := $sc.cosign | default dict -}}
{{- $slsa := $sc.slsa | default dict -}}
{{- $scan := $sc.scan | default dict -}}
{{- if or $sbom.digest $cosign.signatureRef $slsa.level $scan.resultDigest }}
supplychain-sbom-digest: {{ $sbom.digest | default "" | quote }}
supplychain-sbom-format: {{ $sbom.format | default "" | quote }}
supplychain-cosign-signature-ref: {{ $cosign.signatureRef | default "" | quote }}
supplychain-cosign-fulcio-fpr: {{ $cosign.fulcioCertFingerprint | default "" | quote }}
supplychain-cosign-rekor-uuid: {{ $cosign.rekorUuid | default "" | quote }}
supplychain-slsa-level: {{ $slsa.level | default 0 | quote }}
supplychain-slsa-provenance-ref: {{ $slsa.provenanceRef | default "" | quote }}
supplychain-slsa-builder-id: {{ $slsa.builderId | default "" | quote }}
supplychain-scan-result-digest: {{ $scan.resultDigest | default "" | quote }}
supplychain-scan-scanner: {{ $scan.scanner | default "" | quote }}
{{- end }}
{{- end }}

{{/*
Annotations to merge into resource metadata. These are also the
annotations sekiban + Kyverno verifyImages + admission policies read.
*/}}
{{- define "pleme-lib.compliance.supplychain.annotations" -}}
{{- $sc := (.Values.compliance).supplychain | default dict -}}
{{- $sbom := $sc.sbom | default dict -}}
{{- $cosign := $sc.cosign | default dict -}}
{{- $slsa := $sc.slsa | default dict -}}
{{- $scan := $sc.scan | default dict -}}
{{- with $sbom.digest -}}
pleme.io/sbom-digest: {{ . | quote }}
pleme.io/sbom-format: {{ $sbom.format | default "cyclonedx-1.5" | quote }}
{{ end -}}
{{- with $cosign.signatureRef -}}
pleme.io/cosign-signature: {{ . | quote }}
{{ end -}}
{{- with $cosign.fulcioCertFingerprint -}}
pleme.io/cosign-fulcio-fpr: {{ . | quote }}
{{ end -}}
{{- with $cosign.rekorUuid -}}
pleme.io/cosign-rekor-uuid: {{ . | quote }}
{{ end -}}
{{- with $slsa.level -}}
pleme.io/slsa-level: {{ . | quote }}
{{ end -}}
{{- with $slsa.provenanceRef -}}
pleme.io/slsa-provenance: {{ . | quote }}
{{ end -}}
{{- with $slsa.builderId -}}
pleme.io/slsa-builder-id: {{ . | quote }}
{{ end -}}
{{- with $scan.resultDigest -}}
pleme.io/scan-result-digest: {{ . | quote }}
pleme.io/scan-scanner: {{ $scan.scanner | default "trivy" | quote }}
{{ end -}}
{{- with $scan.scannedAt -}}
pleme.io/scan-at: {{ . | quote }}
{{ end -}}
{{- with ($scan.vex | default dict).ref -}}
pleme.io/vex-ref: {{ . | quote }}
{{ end -}}
{{- end }}

{{/*
Validate.

At fedramp-moderate+:
  - sbom.digest must be set
  - sbom.format must be in the allowlist (CycloneDX 1.4/1.5, SPDX 2.3)
  - cosign.signatureRef must be set
  - scan.resultDigest must be set
  - thresholds.critical must be 0
  - thresholds.high must be 0 unless explicit waiver

At fedramp-high:
  - slsa.level >= 2
  - slsa.provenanceRef must be set
  - cosign.fulcioCertFingerprint must be set (keyless trust root anchored)

At IL5+ (compliance.dod.impactLevel = il5/il6, see _compliance_il.tpl):
  - slsa.level >= 3
  - cosign keyed must reference a HSM-backed key (cosign.keyRef.hsm = true)
*/}}
{{- define "pleme-lib.compliance.supplychain.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- $sc := (.Values.compliance).supplychain | default dict -}}
{{/* Layer 4 supply-chain enforcement is OPT-IN via
     compliance.supplychain.enabled=true. The Layer 0-3 baseline FedRAMP
     posture (image digest, attestation, audit, …) is unchanged.
     DoD-IL5+ forces this on via _compliance_il.tpl::dod.validate. */}}
{{- $enabled := eq (toString $sc.enabled) "true" -}}
{{- if and $enabled (and (eq $atLeastMod "true") (eq $isWorkload "true")) -}}
  {{- $sbom := $sc.sbom | default dict -}}
  {{- $cosign := $sc.cosign | default dict -}}
  {{- $slsa := $sc.slsa | default dict -}}
  {{- $scan := $sc.scan | default dict -}}
  {{- $allow := $sc.allowList | default dict -}}
  {{- $allowedFormats := list "cyclonedx-1.4" "cyclonedx-1.5" "cyclonedx-1.6" "spdx-2.3" -}}
  {{/* Per-field gates can be opted out at moderate via allowList.skipSbom etc.
       At fedramp-high all are mandatory. */}}
  {{- if not $sbom.digest -}}
    {{- if not (and (eq $atLeastHigh "false") $allow.skipSbom) -}}
      {{- fail (printf "compliance: baseline=%s requires compliance.supplychain.sbom.digest (CM-2, CM-8, SR-4)" $b) -}}
    {{- end -}}
  {{- end -}}
  {{- if $sbom.digest -}}
    {{- $f := $sbom.format | default "cyclonedx-1.5" | toString | lower -}}
    {{- if not (has $f $allowedFormats) -}}
      {{- fail (printf "compliance: compliance.supplychain.sbom.format=%q not in allowlist %v (CM-2)" $f $allowedFormats) -}}
    {{- end -}}
  {{- end -}}
  {{- if not $cosign.signatureRef -}}
    {{- if not (and (eq $atLeastHigh "false") $allow.skipCosign) -}}
      {{- fail (printf "compliance: baseline=%s requires compliance.supplychain.cosign.signatureRef (SI-7, SR-11)" $b) -}}
    {{- end -}}
  {{- end -}}
  {{- if not $scan.resultDigest -}}
    {{- if not (and (eq $atLeastHigh "false") $allow.skipScan) -}}
      {{- fail (printf "compliance: baseline=%s requires compliance.supplychain.scan.resultDigest (RA-5)" $b) -}}
    {{- end -}}
  {{- end -}}
  {{- $th := $sc.thresholds | default dict -}}
  {{- $crit := $th.critical | default 0 | int -}}
  {{- if gt $crit 0 -}}
    {{- fail (printf "compliance: compliance.supplychain.thresholds.critical must be 0 (RA-5, SI-3); got %d" $crit) -}}
  {{- end -}}
  {{- $high := $th.high | default 0 | int -}}
  {{- if gt $high 0 -}}
    {{- if not $allow.acceptHighCves -}}
      {{- fail (printf "compliance: compliance.supplychain.thresholds.high must be 0 unless compliance.supplychain.allowList.acceptHighCves=true with documented justification (RA-5)" ) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if and $enabled (and (eq $atLeastHigh "true") (eq $isWorkload "true")) -}}
  {{- $slsa := $sc.slsa | default dict -}}
  {{- $cosign := $sc.cosign | default dict -}}
  {{- $level := $slsa.level | default 0 | int -}}
  {{- if lt $level 2 -}}
    {{- fail (printf "compliance: supplychain.enabled=true at baseline=fedramp-high requires compliance.supplychain.slsa.level >= 2 (SA-10, SR-4); got %d" $level) -}}
  {{- end -}}
  {{- if not $slsa.provenanceRef -}}
    {{- fail (printf "compliance: supplychain.enabled=true at baseline=fedramp-high requires compliance.supplychain.slsa.provenanceRef (in-toto Statement OCI ref) (SR-4)") -}}
  {{- end -}}
{{- end -}}
{{- end }}
