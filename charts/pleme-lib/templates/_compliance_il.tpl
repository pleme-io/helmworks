{{/*
pleme-lib: compliance — DoD Cloud Computing SRG Impact Level (IL2/IL4/IL5/IL6)

Single value `compliance.dod.impactLevel` selects the DoD impact-level
overlay. Each level layers onto the prior:

  il2  — public / non-CUI               ≈ FedRAMP Moderate (no extras)
  il4  — CUI mission-support             ≈ FedRAMP Moderate + DoD overlay
  il5  — CUI national-security           ≈ FedRAMP High + DoD IL5 overlay
                                         + FIPS 140-3 mandatory
                                         + dedicated tenancy
                                         + CAC/PIV admin auth
                                         + IronBank base images
                                         + SLSA L3 minimum
  il6  — classified up to SECRET         + hardware-rooted attestation
                                         + SCIF physical hosting
                                         + Type-1 crypto
                                         + classified air-gap network
                                         + no commercial cloud

Reference: DoD Cloud Computing SRG v1r4 (Jan 2022), DISA RME.

The IL primitive does NOT replace fedramp baselines — it ADDS DoD-specific
constraints on top. A workload at fedramp-high + il5 is the canonical
shape. fedramp-high alone is sufficient for civilian agencies; fedramp-high
+ il5 is required for DoD CUI national-security workloads.
*/}}

{{- define "pleme-lib.compliance.dod.impactLevel" -}}
{{- $d := (.Values.compliance).dod | default dict -}}
{{- $explicit := $d.impactLevel | default "" | toString | lower | trim -}}
{{- if ne $explicit "" -}}{{ $explicit }}
{{- else -}}
  {{- /* pleme-lib 0.9.0+: derive from resolved overlay list */ -}}
  {{- $overlays := include "pleme-lib.overlay.list" . | fromYamlArray -}}
  {{- if has "dod-il6" $overlays -}}il6
  {{- else if has "dod-il5" $overlays -}}il5
  {{- else if has "dod-il4" $overlays -}}il4
  {{- else if has "dod-il2" $overlays -}}il2
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
"true" / "false" — is the impact level >= threshold?
  Threshold ordering: il2 (1) < il4 (2) < il5 (3) < il6 (4)
*/}}
{{- define "pleme-lib.compliance.dod.atLeast" -}}
{{- $ctx := index . 0 -}}
{{- $threshold := index . 1 -}}
{{- $rank := dict "" 0 "il2" 1 "il4" 2 "il5" 3 "il6" 4 -}}
{{- $cur := include "pleme-lib.compliance.dod.impactLevel" $ctx -}}
{{- $curR := index $rank $cur | default 0 -}}
{{- $thrR := index $rank $threshold | default 0 -}}
{{- if ge ($curR | int) ($thrR | int) }}true{{ else }}false{{ end }}
{{- end }}

{{/*
Annotations.
*/}}
{{- define "pleme-lib.compliance.dod.annotations" -}}
{{- $il := include "pleme-lib.compliance.dod.impactLevel" . -}}
{{- if $il }}
pleme.io/dod-impact-level: {{ $il | quote }}
pleme.io/dod-srg-version: "v1r4"
{{- end }}
{{- end }}

{{/*
Manifest data.
*/}}
{{- define "pleme-lib.compliance.dod.manifestData" -}}
{{- $il := include "pleme-lib.compliance.dod.impactLevel" . -}}
{{- if $il }}
dod-impact-level: {{ $il | quote }}
dod-srg-version: "v1r4"
{{- end }}
{{- end }}

{{/*
Validate.

At il4+:
  - airgap.enabled must be true (DoD CUI requires registry boundary)
  - compliance.baseline must be at least fedramp-moderate

At il5+:
  - fips.enabled must be true                    (FIPS 140-3 end-to-end)
  - compliance.baseline must be fedramp-high     (overlay of FedRAMP-High)
  - supplychain.slsa.level >= 3                  (SLSA L3 minimum)
  - supplychain.cosign.fulcioCertFingerprint OR cosign.keyRef.hsm = true
                                                  (HSM-backed cosign key
                                                   or DoD-PKI keyless)
  - airgap.requireSignedImages = true            (already enforced at high)

At il6:
  - All il5 +
  - attestation.hardwareRoot = "tpm2" or "caliptra"
  - network.egress = "cds-only" (no Internet, only Cross Domain Solution)
*/}}
{{- define "pleme-lib.compliance.dod.validate" -}}
{{- $il := include "pleme-lib.compliance.dod.impactLevel" . -}}
{{- if eq $il "" -}}
  {{/* No DoD impact level declared — nothing to validate */}}
{{- else -}}
  {{- $allowedLevels := list "il2" "il4" "il5" "il6" -}}
  {{- if not (has $il $allowedLevels) -}}
    {{- fail (printf "compliance: compliance.dod.impactLevel=%q must be one of %v" $il $allowedLevels) -}}
  {{- end -}}
  {{- $b := include "pleme-lib.compliance.baseline" . -}}
  {{- $atLeastIl4 := include "pleme-lib.compliance.dod.atLeast" (list . "il4") -}}
  {{- $atLeastIl5 := include "pleme-lib.compliance.dod.atLeast" (list . "il5") -}}
  {{- $atLeastIl6 := include "pleme-lib.compliance.dod.atLeast" (list . "il6") -}}
  {{- $atLeastFRMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
  {{- $atLeastFRHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
  {{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}

  {{- if eq $atLeastIl4 "true" -}}
    {{- if ne $atLeastFRMod "true" -}}
      {{- fail (printf "compliance: dod.impactLevel=%s requires compliance.baseline >= fedramp-moderate; got %q (DoD CC SRG v1r4)" $il $b) -}}
    {{- end -}}
    {{- if eq $isWorkload "true" -}}
      {{- /* airgap.enabled OR airgap-* overlay declared satisfies the registry-boundary requirement. */ -}}
      {{- if ne (include "pleme-lib.compliance.airgap.enabled" .) "true" -}}
        {{- fail (printf "compliance: dod.impactLevel=%s requires compliance.airgap.enabled=true OR airgap-consumer/airgap-registry-mirror in compliance.overlays (DoD CUI registry boundary; SC-7(11))" $il) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- if eq $atLeastIl5 "true" -}}
    {{- if ne $atLeastFRHigh "true" -}}
      {{- fail (printf "compliance: dod.impactLevel=%s requires compliance.baseline=fedramp-high; got %q (FedRAMP-High + IL5 overlay)" $il $b) -}}
    {{- end -}}
    {{- if eq $isWorkload "true" -}}
      {{- $f := (.Values.compliance).fips | default dict -}}
      {{- if ne (toString $f.enabled) "true" -}}
        {{- fail (printf "compliance: dod.impactLevel=%s requires compliance.fips.enabled=true (FIPS 140-3 end-to-end; SC-13, IA-7)" $il) -}}
      {{- end -}}
      {{- $sc := (.Values.compliance).supplychain | default dict -}}
      {{- if ne (toString $sc.enabled) "true" -}}
        {{- fail (printf "compliance: dod.impactLevel=%s requires compliance.supplychain.enabled=true (CM-2, CM-8, SR-3); the IL5 overlay forces SBOM + cosign + SLSA-L3 + scan attestation" $il) -}}
      {{- end -}}
      {{- $slsa := $sc.slsa | default dict -}}
      {{- $level := $slsa.level | default 0 | int -}}
      {{- if lt $level 3 -}}
        {{- fail (printf "compliance: dod.impactLevel=%s requires compliance.supplychain.slsa.level >= 3 (DoD IL5 overlay; SR-4); got %d" $il $level) -}}
      {{- end -}}
      {{- $cosign := $sc.cosign | default dict -}}
      {{- $hsm := eq (toString ($cosign.keyRef).hsm) "true" -}}
      {{- if not (or $cosign.fulcioCertFingerprint $hsm) -}}
        {{- fail (printf "compliance: dod.impactLevel=%s requires compliance.supplychain.cosign.fulcioCertFingerprint (DoD-PKI keyless) OR compliance.supplychain.cosign.keyRef.hsm=true (HSM-backed key); SC-12(2)" $il) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- if eq $atLeastIl6 "true" -}}
    {{- if eq $isWorkload "true" -}}
      {{- $att := (.Values.compliance).attestation | default dict -}}
      {{- $hw := $att.hardwareRoot | default "" | toString | lower -}}
      {{- if not (or (eq $hw "tpm2") (eq $hw "caliptra")) -}}
        {{- fail (printf "compliance: dod.impactLevel=il6 requires compliance.attestation.hardwareRoot ∈ {tpm2, caliptra}; got %q (SC-12(2), SR-11(2))" $hw) -}}
      {{- end -}}
      {{- $net := (.Values.compliance).network | default dict -}}
      {{- $egress := $net.egress | default "" | toString | lower -}}
      {{- if ne $egress "cds-only" -}}
        {{- fail (printf "compliance: dod.impactLevel=il6 requires compliance.network.egress=\"cds-only\" (Cross Domain Solution; classified-air-gap; SC-7); got %q" $egress) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
