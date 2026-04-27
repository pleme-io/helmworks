{{/*
pleme-lib: servicemonitor named template

ServiceMonitor is mandatory at compliance baseline >= fedramp-moderate
(AU-2, AU-12, SI-4). The compliance.audit.validate validator forces
monitoring.enabled=true at moderate+, so the existing `.Values.monitoring.enabled`
gate naturally becomes always-true.
*/}}

{{- define "pleme-lib.servicemonitor" -}}
{{- if (.Values.monitoring).enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- $resAnnotations := include "pleme-lib.resourceAnnotations" . }}
  {{- if $resAnnotations }}
  annotations:
    {{- $resAnnotations | nindent 4 }}
  {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: {{ (.Values.monitoring).port | default "http" }}
      path: {{ (.Values.monitoring).path | default "/metrics" }}
      interval: {{ (.Values.monitoring).interval | default "30s" }}
      scrapeTimeout: {{ (.Values.monitoring).scrapeTimeout | default "10s" }}
{{- end }}
{{- end }}
