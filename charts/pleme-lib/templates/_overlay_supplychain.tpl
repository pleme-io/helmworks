{{/*
Overlay: supplychain
Source: NIST 800-53 SR-3/4/11, SA-10/11/12, RA-5, CM-2/8/10, SI-3/7
        + EO 14028 / NIST 800-218 SSDF
        + DoD IronBank acceptance criteria
        + Sigstore cosign / SLSA 1.0
*/}}

{{- define "pleme-lib.overlay.supplychain.requires" -}}{{- end }}

{{- define "pleme-lib.overlay.supplychain.controls" -}}
CM-2,CM-8,CM-10,RA-5,SA-10,SA-12,SI-7,SR-3,SR-4,SR-11
{{- end }}

{{- define "pleme-lib.overlay.supplychain.validate" -}}
{{- include "pleme-lib.compliance.supplychain.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.supplychain.annotations" -}}
compliance.pleme.io/overlay-supplychain: "true"
{{ include "pleme-lib.compliance.supplychain.annotations" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.supplychain.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.supplychain.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.supplychain.manifestData" -}}
overlay-supplychain: "true"
{{ include "pleme-lib.compliance.supplychain.manifestData" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.supplychain.podEnv" -}}{{- end }}

{{- define "pleme-lib.overlay.supplychain.imagePullSecrets" -}}{{- end }}

{{/* Admission policy: Kyverno verifyImages is the canonical mechanism
     for cosign signature verification at admission. The supplychain
     overlay declares the policy here; consumer charts that include the
     pleme-lib.compliance.admissionPolicies template get it deployed. */}}
{{- define "pleme-lib.overlay.supplychain.kyvernoPolicy" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pleme-overlay-supplychain-verify-images
  annotations:
    pleme.io/overlay: supplychain
    pleme.io/controls: "SI-7,SR-3,SR-4,SR-11"
spec:
  validationFailureAction: Enforce
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-cosign-signature
      match:
        any:
          - resources:
              kinds: ["Pod"]
      verifyImages:
        - imageReferences:
            - "*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      {{- $cosign := ((.Values.compliance).supplychain).cosign | default dict }}
                      {{- $cosign.publicKey | default "# inject via .Values.compliance.supplychain.cosign.publicKey" | nindent 22 }}
{{ end }}
{{- define "pleme-lib.overlay.supplychain.gatekeeperConstraint" -}}{{- end }}
