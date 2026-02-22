{{/*
pleme-lib: servicemonitor named template
*/}}

{{- define "pleme-lib.servicemonitor" -}}
{{- if .Values.monitoring.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: {{ .Values.monitoring.port | default "http" }}
      path: {{ .Values.monitoring.path | default "/metrics" }}
      interval: {{ .Values.monitoring.interval | default "30s" }}
      scrapeTimeout: {{ .Values.monitoring.scrapeTimeout | default "10s" }}
{{- end }}
{{- end }}
