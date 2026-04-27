{{/*
pleme-lib: poddisruptionbudget named template

When `.Values.compliance.baseline` >= fedramp-high, a compliance PDB is
emitted automatically (SC-5, CP-2). Consumers may still set `.Values.pdb` to
override minAvailable/maxUnavailable.
*/}}

{{- define "pleme-lib.pdb" -}}
{{- $availabilityRequired := include "pleme-lib.compliance.availability.required" . -}}
{{- if eq $availabilityRequired "true" -}}
{{ include "pleme-lib.compliance.availability.pdb" . }}
{{- else if (.Values.pdb).enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  {{- if (.Values.pdb).minAvailable }}
  minAvailable: {{ (.Values.pdb).minAvailable }}
  {{- else if (.Values.pdb).maxUnavailable }}
  maxUnavailable: {{ (.Values.pdb).maxUnavailable }}
  {{- else }}
  minAvailable: 1
  {{- end }}
{{- end }}
{{- end }}
