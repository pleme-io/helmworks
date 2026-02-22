{{/*
pleme-lib: serviceaccount named template
*/}}

{{- define "pleme-lib.serviceaccount" -}}
{{- if (.Values.serviceAccount).create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "pleme-lib.serviceAccountName" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- with (.Values.serviceAccount).annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
