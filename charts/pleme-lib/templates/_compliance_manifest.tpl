{{/*
pleme-lib: compliance — control coverage manifest

Emits a ConfigMap describing what compliance posture this Release claims
and which controls it covers. Read by:
  - kensa (compliance engine) for OSCAL evidence collection
  - sekiban (admission webhook) for cross-checking annotation claims
  - audit pipelines that need to enumerate "what's deployed and what does it claim"

The manifest is deterministic: same values -> same manifest -> same BLAKE3
hash. tameshi can fingerprint the manifest as a compliance dimension input.
*/}}

{{- define "pleme-lib.compliance.manifest" -}}
{{- $enabled := include "pleme-lib.compliance.enabled" . -}}
{{- if eq $enabled "true" }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "pleme-lib.fullname" . }}-compliance-manifest
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    compliance.pleme.io/manifest: "true"
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
data:
  baseline: {{ include "pleme-lib.compliance.baseline" . | quote }}
  framework: "nist-800-53-rev5"
  enforce: {{ include "pleme-lib.compliance.enforce" . | quote }}
  controls: {{ include "pleme-lib.compliance.controls" . | quote }}
  release: {{ .Release.Name | quote }}
  chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
  appVersion: {{ .Chart.AppVersion | default "" | quote }}
  workload: {{ include "pleme-lib.fullname" . | quote }}
  namespace: {{ include "pleme-lib.namespace" . | quote }}
  managed-by: {{ .Release.Service | quote }}
  schema-version: "4"
  overlays: {{ include "pleme-lib.overlay.list" . | fromYamlArray | toJson | quote }}
  {{- /* pleme-lib 0.9.0+: per-overlay manifest fragments dispatch via registry. */ -}}
  {{- include "pleme-lib.overlay.dispatchAll" (list "manifestData" .) | nindent 2 }}
{{- end }}
{{- end }}
