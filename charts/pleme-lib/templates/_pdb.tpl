{{/*
pleme-lib: poddisruptionbudget named template
*/}}

{{- define "pleme-lib.pdb" -}}
{{- if .Values.pdb.enabled }}
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
  {{- if .Values.pdb.minAvailable }}
  minAvailable: {{ .Values.pdb.minAvailable }}
  {{- else if .Values.pdb.maxUnavailable }}
  maxUnavailable: {{ .Values.pdb.maxUnavailable }}
  {{- else }}
  minAvailable: 1
  {{- end }}
{{- end }}
{{- end }}
