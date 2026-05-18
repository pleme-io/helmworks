{{/*
pleme-reconciler.driftPolicyConfigMap

Renders a typed DriftPolicy ConfigMap mirroring `magma_drift::DriftPolicy`.
Consumed by any operator running magma-drift's `classify(plan, policy)`.

Usage in consumer template:

  {{- include "pleme-reconciler.driftPolicyConfigMap" . }}

Skipped entirely when `reconciler.driftPolicy.enabled: false`.

The ConfigMap key `policy.json` carries the serialized DriftPolicy.
Operators mount the ConfigMap + read this key at startup. Schema
mirrors what `serde_json::from_value::<DriftPolicy>(...)` accepts on
the Rust side.

Per theory/CONVERGENCE-SUBSTRATE.md §IV.1 + magma-drift docs.
*/}}
{{- define "pleme-reconciler.driftPolicyConfigMap" -}}
{{- $policy := .Values.reconciler.driftPolicy | default dict -}}
{{- if $policy.enabled }}
{{- $kind := .Values.reconciler.kind | default (printf "%s" .Chart.Name) -}}
{{- $name := $policy.name | default (printf "%s-drift-policy" $kind) -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $name }}
  labels:
    app.kubernetes.io/name:        {{ .Chart.Name | quote }}
    app.kubernetes.io/component:   drift-policy
    app.kubernetes.io/managed-by:  {{ .Release.Service | quote }}
    magma.pleme.io/reconciler:     {{ $kind | quote }}
    magma.pleme.io/policy-shape:   "drift-v1"
  {{- include "pleme-reconciler.attestationLabels" . | nindent 4 }}
data:
  policy.json: |
{{ $policy | toJson | indent 4 }}
{{- end }}
{{- end }}
