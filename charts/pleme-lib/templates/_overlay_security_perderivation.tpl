{{/*
Overlay: security-perderivation
Source: super-cache-ci per-derivation security layer
        theory/SUPER-CACHE-CI-SECURITY.md
        NIST 800-53 Rev 5 SI-7, CM-14, SR-11 (L-sign) · CM-8 (L-sbom) ·
        RA-5, SI-2 (L-cve/vex) · SR-3/4, SA-10 (L-provenance) ·
        AU-2/12 (L-transparency) · CM-14, SR-11 (L-admission)

The umbrella overlay for the six-layer per-derivation security surface.
It REQUIRES supplychain (the shipped verdict surface) and layers the
tool/verdict-store/key/transparency/admission knobs on top. Turned on by
`security.perDerivation.enabled=true` (back-compat synthesize) OR by
declaring `security-perderivation` in compliance.overlays.
*/}}

{{- define "pleme-lib.overlay.security-perderivation.requires" -}}
supplychain
{{- end }}

{{- define "pleme-lib.overlay.security-perderivation.controls" -}}
{{- include "pleme-lib.compliance.perDerivation.controls" . -}}
{{- end }}

{{- define "pleme-lib.overlay.security-perderivation.validate" -}}
{{- include "pleme-lib.compliance.perDerivation.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.security-perderivation.annotations" -}}
compliance.pleme.io/overlay-security-perderivation: "true"
{{ include "pleme-lib.compliance.perDerivation.annotations" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.security-perderivation.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.security-perderivation.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.security-perderivation.manifestData" -}}
overlay-security-perderivation: "true"
{{ include "pleme-lib.compliance.perDerivation.manifestData" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.security-perderivation.podEnv" -}}{{- end }}

{{- define "pleme-lib.overlay.security-perderivation.imagePullSecrets" -}}{{- end }}

{{/* L-admission — the runtime-enforcement layer.

     The supplychain overlay already emits a Kyverno verifyImages
     ClusterPolicy (verify-cosign-signature). This overlay adds the
     COMPLEMENTARY policy: every admitted Pod must carry the
     per-derivation verdict annotations the shipped
     _compliance_supplychain.tpl emits (sbom-digest / cosign-signature /
     scan-result-digest). Enforce, not Audit — this is the §8.4
     only-mitigated → runtime-enforced move.

     Emitted only when layers.admission.enforce is true. mode selects the
     failure action (kyverno=Enforce). When mode=policy-controller the
     operator owns a Sigstore ClusterImagePolicy out-of-band and this
     Kyverno policy is omitted. */}}
{{- define "pleme-lib.overlay.security-perderivation.kyvernoPolicy" -}}
{{- $s := (.Values.security | default dict).perDerivation | default dict -}}
{{- $adm := ($s.layers | default dict).admission | default dict -}}
{{- $mode := $adm.mode | default "kyverno" | toString | lower -}}
{{- if and (eq (toString $adm.enforce) "true") (eq $mode "kyverno") -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pleme-overlay-security-perderivation-require-verdict-annotations
  annotations:
    pleme.io/overlay: security-perderivation
    pleme.io/controls: "CM-8,RA-5,SI-7,SR-3,SR-4,SR-11"
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-supply-chain-verdict-annotations
      match:
        any:
          - resources:
              kinds: ["Pod"]
              selector:
                matchLabels:
                  compliance.pleme.io/manifest: "false"
      validate:
        message: "per-derivation security requires pleme.io/{sbom-digest,cosign-signature,scan-result-digest} annotations (CM-8, RA-5, SI-7)"
        pattern:
          metadata:
            annotations:
              pleme.io/sbom-digest: "?*"
              pleme.io/cosign-signature: "?*"
              pleme.io/scan-result-digest: "?*"
{{ end }}
{{- end }}

{{- define "pleme-lib.overlay.security-perderivation.gatekeeperConstraint" -}}{{- end }}
