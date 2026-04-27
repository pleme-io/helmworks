{{/*
Overlay: fips
Source: FIPS 140-3 / NIST CMVP; NIST 800-53 IA-7, SC-12, SC-13, SC-17, SC-28(1)
*/}}

{{- define "pleme-lib.overlay.fips.requires" -}}{{- end }}

{{- define "pleme-lib.overlay.fips.controls" -}}
IA-7,SC-12(2),SC-13,SC-17,SC-28(1)
{{- end }}

{{- define "pleme-lib.overlay.fips.validate" -}}
{{- include "pleme-lib.compliance.fips.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.fips.annotations" -}}
compliance.pleme.io/overlay-fips: "true"
{{ include "pleme-lib.compliance.fips.annotations" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.fips.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.fips.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.fips.manifestData" -}}
overlay-fips: "true"
{{ include "pleme-lib.compliance.fips.manifestData" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.fips.podEnv" -}}
{{- include "pleme-lib.compliance.fips.env" . -}}
{{- end }}

{{- define "pleme-lib.overlay.fips.imagePullSecrets" -}}{{- end }}

{{/* FIPS admission policy: assert the workload's image is from the
     FIPS-mode allowlist (or air-gap is active). */}}
{{- define "pleme-lib.overlay.fips.kyvernoPolicy" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pleme-overlay-fips-image-base
  annotations:
    pleme.io/overlay: fips
    pleme.io/controls: "SC-13,IA-7,SC-12(2)"
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-fips-image-base
      match:
        any:
          - resources:
              kinds: ["Pod"]
              namespaceSelector:
                matchExpressions:
                  - key: pleme.io/fips-mode
                    operator: Exists
      validate:
        message: "fips overlay requires image from registry1.dso.mil/, cgr.dev/chainguard/, or registry.access.redhat.com/ubi*"
        anyPattern:
          - spec:
              containers:
                - image: "registry1.dso.mil/*"
          - spec:
              containers:
                - image: "cgr.dev/chainguard/*"
          - spec:
              containers:
                - image: "registry.access.redhat.com/ubi*"
{{ end }}
{{- define "pleme-lib.overlay.fips.gatekeeperConstraint" -}}{{- end }}
