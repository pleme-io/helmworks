{{/*
pleme-lib: priorityclass named template

Cluster-scoped PriorityClasses with configurable prefix.
Default 4-tier: critical (10M), data (10.5M), background (1M), batch (100k non-preempting).
*/}}

{{- define "pleme-lib.priorityclasses" -}}
{{- $prefix := (.Values.priorityClasses).prefix | default (include "pleme-lib.fullname" .) -}}
{{- range (.Values.priorityClasses).classes }}
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: {{ $prefix }}-{{ .name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
{{- /* int64: a YAML integer arrives as float64, and 10000000 prints as
       1e+07, which the API server refuses for the int32 `value`. */}}
value: {{ .value | int64 }}
globalDefault: {{ .globalDefault | default false }}
preemptionPolicy: {{ .preemptionPolicy | default "PreemptLowerPriority" }}
description: {{ .description | default "" | quote }}
{{- end }}
{{- end }}
