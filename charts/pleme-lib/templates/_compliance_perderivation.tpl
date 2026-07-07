{{/*
pleme-lib: compliance — per-derivation security (the enjulho LAYERED surface)

ONE typed config surface for super-cache-ci's per-derivation security layer.
The single umbrella toggle is `.Values.security.perDerivation.enabled`; it
composes the ALREADY-SHIPPED `compliance.supplychain.*` verdict surface
(_compliance_supplychain.tpl) into six ORDERED layers, each a knob-set that
selects HOW a verdict is produced/enforced (the supplychain.* fields carry
WHAT the verdict IS). Because super-cache-ci is content-addressed
(gen-pdc PDC clause 4: addr(n) is simultaneously cache key, incremental
boundary, AND attestation address), every verdict is per-derivation
build-once-reuse — sign/SBOM/scan/attest each unique content hash ONCE,
keyed by that hash; every consumer of the hash inherits the verdict.

THE SIX LAYERS (ordered — each verdict feeds the next):

  L-sign        signature       Nix ed25519 store-path sig (sui) + cosign image sig
  L-sbom        sbom            sbomnix (closure-driven) | syft — CM-8 inventory
  L-cve/vex     cve             Trivy | Grype scan (+ OpenVEX justification) — RA-5
  L-provenance  provenance      SLSA L3 in-toto DSSE + VSA — SR-3/4/11 (new in Rev5)
  L-transparency transparency   rekor (online) | offline tameshi receipt (air-gap void)
  L-admission   —               Kyverno verifyImages / Sigstore policy-controller (Enforce)

OSS-FIRST, no-NIH. The engines are the industry standards (Nix-native
ed25519, Sigstore cosign/rekor, sbomnix, Trivy, SLSA/in-toto, Kyverno
verifyImages) encapsulated behind typed config — the same pattern as the
compliance.baseline toggle. pleme-io content is reserved for the four
tested voids Sigstore/SLSA leave open: offline/air-gapped inclusion
verification, a re-derivable compliance proof, the BLAKE3 content-hash↔
Nix-store binding, and eBPF kernel-time enforcement. See
theory/SUPER-CACHE-CI-SECURITY.md.

Keys are NEVER plaintext — every signing/cosign key is a cofre / ESO
SecretRef (name + key), matching the shipped cofre SecretRef discipline.

Configuration is in `.Values.security.perDerivation`:

  enabled: true                        # umbrella — turn the whole layer on
  verdictStore:
    backend: "sui-postgres"            # ContentHash-keyed sibling table (§4.4)
    contentKey: "blake3"               # the PDC clause-4 shared key
  layers:
    sign:
      storePathSigning: true           # sui ed25519 NAR signing (L-sign foundation)
      cosignKeyRef: { name: "", key: "" }   # cofre/ESO SecretRef — NEVER inline
    sbom:
      tool: "sbomnix"                  # sbomnix (closure-driven) | syft
      closureDriven: true
    cve:
      scanner: "trivy"                 # trivy | grype | anchore
      dbEpochTtlHours: 24              # §4.3 — the one NON-timeless verdict
    provenance:
      slsaLevel: 3                     # SLSA Build level (maturity metric)
      vsaRef: ""                       # verification-summary attestation, optional
    transparency:
      mode: "rekor"                    # rekor (online) | offline-tameshi (air-gap void)
      offlineReceiptRef: ""            # cartorio offline inclusion proof (IL6)
    admission:
      enforce: true                    # Enforce (not Audit); un-suspend Kyverno
      mode: "kyverno"                  # kyverno | policy-controller

Tier-honest (never round up): the six-layer coverage-across-consumers is a
CeilingC1 property (a graph-reachability quantifier — a memoized fixpoint +
a CI forcing-function, not a Rust type theorem); a single verdict blob's
tamper-evidence IS truly-unrepresentable modulo BLAKE3. The CVE verdict
carries a scanned-at/db-epoch time dimension (C2 external-world ceiling).
Two external gates are NAMED, never claimed done: FIPS-140 CMVP
validated-build and a live 3PAO assessment pass.
*/}}

{{/*
Is the per-derivation security layer on? "true" / "false".
Umbrella toggle; IL5+ forces supplychain on (see _compliance_il.tpl) — an
operator running IL5 SHOULD also set this to select tools + admission mode.
*/}}
{{- define "pleme-lib.compliance.perDerivation.enabled" -}}
{{- $s := (.Values.security | default dict).perDerivation | default dict -}}
{{- if eq (toString $s.enabled) "true" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
The ordered layer roster (single source of truth for the taxonomy).
*/}}
{{- define "pleme-lib.compliance.perDerivation.layers" -}}
sign,sbom,cve-vex,provenance-vsa,transparency,admission
{{- end }}

{{/*
Per-layer NIST 800-53 Rev 5 control crosswalk (the layer → control map).
*/}}
{{- define "pleme-lib.compliance.perDerivation.controls" -}}
SI-7,CM-14,SR-11,CM-8,RA-5,SI-2,SR-3,SR-4,SA-10,AU-2,AU-12
{{- end }}

{{/*
Annotations. Surface the layer taxonomy + the verdict-store key + the
transparency/admission modes so sekiban / Kyverno / audit pipelines can
enumerate the per-derivation posture. Composes with (does not replace) the
supplychain annotations which carry the verdict VALUES.
*/}}
{{- define "pleme-lib.compliance.perDerivation.annotations" -}}
{{- if eq (include "pleme-lib.compliance.perDerivation.enabled" .) "true" -}}
{{- $s := (.Values.security).perDerivation | default dict -}}
{{- $vs := $s.verdictStore | default dict -}}
{{- $layers := $s.layers | default dict -}}
{{- $tr := $layers.transparency | default dict -}}
{{- $adm := $layers.admission | default dict -}}
pleme.io/security-per-derivation: "true"
pleme.io/security-layers: {{ include "pleme-lib.compliance.perDerivation.layers" . | quote }}
pleme.io/security-verdict-store: {{ $vs.backend | default "sui-postgres" | quote }}
pleme.io/security-verdict-key: {{ $vs.contentKey | default "blake3" | quote }}
pleme.io/security-transparency-mode: {{ $tr.mode | default "rekor" | quote }}
pleme.io/security-admission-mode: {{ $adm.mode | default "kyverno" | quote }}
{{- end -}}
{{- end }}

{{/*
Manifest data — surfaces the per-layer posture in the compliance ConfigMap
so audit tooling enumerates the per-derivation claims.
*/}}
{{- define "pleme-lib.compliance.perDerivation.manifestData" -}}
{{- if eq (include "pleme-lib.compliance.perDerivation.enabled" .) "true" -}}
{{- $s := (.Values.security).perDerivation | default dict -}}
{{- $vs := $s.verdictStore | default dict -}}
{{- $layers := $s.layers | default dict -}}
{{- $sign := $layers.sign | default dict -}}
{{- $sbom := $layers.sbom | default dict -}}
{{- $cve := $layers.cve | default dict -}}
{{- $prov := $layers.provenance | default dict -}}
{{- $tr := $layers.transparency | default dict -}}
{{- $adm := $layers.admission | default dict -}}
security-per-derivation: "true"
security-layers: {{ include "pleme-lib.compliance.perDerivation.layers" . | quote }}
security-verdict-store: {{ $vs.backend | default "sui-postgres" | quote }}
security-verdict-key: {{ $vs.contentKey | default "blake3" | quote }}
security-layer-sign-store-path: {{ $sign.storePathSigning | default false | quote }}
security-layer-sbom-tool: {{ $sbom.tool | default "sbomnix" | quote }}
security-layer-cve-scanner: {{ $cve.scanner | default "trivy" | quote }}
security-layer-cve-db-epoch-ttl-hours: {{ $cve.dbEpochTtlHours | default 24 | quote }}
security-layer-provenance-slsa-level: {{ $prov.slsaLevel | default 0 | quote }}
security-layer-transparency-mode: {{ $tr.mode | default "rekor" | quote }}
security-layer-admission-mode: {{ $adm.mode | default "kyverno" | quote }}
security-layer-admission-enforce: {{ $adm.enforce | default false | quote }}
{{- end -}}
{{- end }}

{{/*
Validate the per-derivation layered surface.

When security.perDerivation.enabled=true on a workload:
  - compliance.supplychain.enabled MUST be true (single verdict-check path —
    the supplychain overlay validates the actual SBOM/cosign/scan/SLSA
    verdict VALUES; perDerivation adds the layer knobs on top).
  - sbom.tool ∈ {sbomnix, syft}
  - cve.scanner ∈ {trivy, grype, anchore}
  - transparency.mode ∈ {rekor, offline-tameshi}
  - any cosignKeyRef MUST be a SecretRef (name + key) — an inline key is
    rejected (cofre / ESO discipline; SC-12, SC-13).

At fedramp-high (verdict-producer foundation must be armed):
  - layers.sign.storePathSigning MUST be true (the L-sign foundation)
  - layers.admission.enforce MUST be true (Enforce, not Audit — §8.4)

At IL6 (compliance.dod.impactLevel=il6, classified air-gap):
  - transparency.mode MUST be offline-tameshi (rekor is unreachable; the
    offline inclusion proof is the ONLY viable transparency mechanism §6b-1)
*/}}
{{- define "pleme-lib.compliance.perDerivation.validate" -}}
{{- if eq (include "pleme-lib.compliance.perDerivation.enabled" .) "true" -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- if eq $isWorkload "true" -}}
  {{- $s := (.Values.security).perDerivation | default dict -}}
  {{- $layers := $s.layers | default dict -}}
  {{- $sign := $layers.sign | default dict -}}
  {{- $sbom := $layers.sbom | default dict -}}
  {{- $cve := $layers.cve | default dict -}}
  {{- $tr := $layers.transparency | default dict -}}
  {{- $adm := $layers.admission | default dict -}}
  {{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
  {{/* Single verdict-check path: perDerivation FORCES supplychain on. */}}
  {{- $sc := (.Values.compliance | default dict).supplychain | default dict -}}
  {{- if ne (toString $sc.enabled) "true" -}}
    {{- fail (printf "compliance: security.perDerivation.enabled=true requires compliance.supplychain.enabled=true (the per-derivation layer produces the SBOM/cosign/scan/SLSA verdicts the supplychain overlay validates; CM-8, SR-3)") -}}
  {{- end -}}
  {{/* L-sbom tool allowlist */}}
  {{- $sbomTool := $sbom.tool | default "sbomnix" | toString | lower -}}
  {{- $sbomTools := list "sbomnix" "syft" -}}
  {{- if not (has $sbomTool $sbomTools) -}}
    {{- fail (printf "compliance: security.perDerivation.layers.sbom.tool=%q must be one of %v (CM-8)" $sbomTool $sbomTools) -}}
  {{- end -}}
  {{/* L-cve scanner allowlist */}}
  {{- $scanner := $cve.scanner | default "trivy" | toString | lower -}}
  {{- $scanners := list "trivy" "grype" "anchore" -}}
  {{- if not (has $scanner $scanners) -}}
    {{- fail (printf "compliance: security.perDerivation.layers.cve.scanner=%q must be one of %v (RA-5)" $scanner $scanners) -}}
  {{- end -}}
  {{/* L-transparency mode allowlist */}}
  {{- $mode := $tr.mode | default "rekor" | toString | lower -}}
  {{- $modes := list "rekor" "offline-tameshi" -}}
  {{- if not (has $mode $modes) -}}
    {{- fail (printf "compliance: security.perDerivation.layers.transparency.mode=%q must be one of %v (AU-2, AU-12)" $mode $modes) -}}
  {{- end -}}
  {{/* Keys via cofre/ESO SecretRef — NEVER plaintext. An inline `key`/`value`
       field (as opposed to a SecretRef name+key) is rejected. */}}
  {{- $ck := $sign.cosignKeyRef | default dict -}}
  {{- if or (hasKey $ck "value") (hasKey $ck "inline") (hasKey $ck "privateKey") -}}
    {{- fail (printf "compliance: security.perDerivation.layers.sign.cosignKeyRef must be a cofre/ESO SecretRef (name + key), never an inline key (value/inline/privateKey forbidden; SC-12, SC-13)") -}}
  {{- end -}}
  {{- if and $ck.name (not $ck.key) -}}
    {{- fail (printf "compliance: security.perDerivation.layers.sign.cosignKeyRef.name set without .key — a SecretRef needs both (SC-12)") -}}
  {{- end -}}
  {{/* fedramp-high: the verdict-producer foundation must be armed. */}}
  {{- if eq $atLeastHigh "true" -}}
    {{- if ne (toString $sign.storePathSigning) "true" -}}
      {{- fail (printf "compliance: security.perDerivation.enabled=true at baseline=fedramp-high requires layers.sign.storePathSigning=true (the L-sign store-path foundation; SI-7, SR-11)") -}}
    {{- end -}}
    {{- if ne (toString $adm.enforce) "true" -}}
      {{- fail (printf "compliance: security.perDerivation.enabled=true at baseline=fedramp-high requires layers.admission.enforce=true (Kyverno verifyImages must Enforce, not Audit; CM-14, SR-11)") -}}
    {{- end -}}
  {{- end -}}
  {{/* IL6: rekor is unreachable in the classified air-gap → offline only. */}}
  {{- $atLeastIl6 := include "pleme-lib.compliance.dod.atLeast" (list . "il6") -}}
  {{- if eq $atLeastIl6 "true" -}}
    {{- if ne $mode "offline-tameshi" -}}
      {{- fail (printf "compliance: dod.impactLevel=il6 requires security.perDerivation.layers.transparency.mode=offline-tameshi (rekor unreachable in classified air-gap; the offline inclusion proof is the only viable transparency mechanism; SC-7, AU-12)") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
