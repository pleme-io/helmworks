{{/*
Overlays: airgap-consumer / airgap-registry-mirror
Source: NIST 800-53 SC-7(11) / SC-7(12); DoD CC SRG IL4+ registry-boundary requirement
*/}}

{{/* ───────────────────────────── airgap-consumer ─────────────────── */}}

{{- define "pleme-lib.overlay.airgap-consumer.requires" -}}{{- end }}

{{- define "pleme-lib.overlay.airgap-consumer.controls" -}}
SC-7(11),SC-7(12)
{{- end }}

{{- define "pleme-lib.overlay.airgap-consumer.validate" -}}
{{- include "pleme-lib.compliance.airgap.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.airgap-consumer.annotations" -}}
compliance.pleme.io/overlay-airgap-consumer: "true"
{{ end }}

{{- define "pleme-lib.overlay.airgap-consumer.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.airgap-consumer.policies" -}}
{{- $role := include "pleme-lib.compliance.airgap.role" . -}}
{{- if eq $role "consumer" -}}
{{- include "pleme-lib.compliance.airgap.policies" . -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.airgap-consumer.manifestData" -}}
overlay-airgap-consumer: "true"
{{ include "pleme-lib.compliance.airgap.manifestData" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.airgap-consumer.podEnv" -}}{{- end }}

{{- define "pleme-lib.overlay.airgap-consumer.imagePullSecrets" -}}
{{- include "pleme-lib.compliance.airgap.imagePullSecrets" . -}}
{{- end }}


{{/* ───────────────────────────── airgap-registry-mirror ─────────── */}}

{{- define "pleme-lib.overlay.airgap-registry-mirror.requires" -}}{{- end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.controls" -}}
SC-7(11),SC-7(12)
{{- end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.validate" -}}
{{- include "pleme-lib.compliance.airgap.validate" . -}}
{{- include "pleme-lib.compliance.mirror.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.annotations" -}}
compliance.pleme.io/overlay-airgap-registry-mirror: "true"
{{ end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.policies" -}}
{{- $role := include "pleme-lib.compliance.airgap.role" . -}}
{{- if eq $role "registry-mirror" -}}
{{- include "pleme-lib.compliance.airgap.policies" . -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.manifestData" -}}
overlay-airgap-registry-mirror: "true"
{{ include "pleme-lib.compliance.airgap.manifestData" . | trim }}
{{ include "pleme-lib.compliance.mirror.manifestData" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.podEnv" -}}{{- end }}

{{- define "pleme-lib.overlay.airgap-registry-mirror.imagePullSecrets" -}}{{- end }}

{{/* Admission-policy surfaces: empty for now. Air-gap registry-boundary
     enforcement comes from Kyverno's verifyImages and from the local
     registry's signature verification, not a generic ClusterPolicy. */}}
{{- define "pleme-lib.overlay.airgap-consumer.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.airgap-consumer.gatekeeperConstraint" -}}{{- end }}
{{- define "pleme-lib.overlay.airgap-registry-mirror.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.airgap-registry-mirror.gatekeeperConstraint" -}}{{- end }}
