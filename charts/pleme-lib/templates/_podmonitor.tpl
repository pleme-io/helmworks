{{/*
pleme-lib: podmonitor named template

PodMonitor for pods not behind a Service (CNPG, Valkey, StatefulSets).
*/}}

{{- define "pleme-lib.podmonitor" -}}
{{- if .Values.podMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  {{- with .Values.podMonitor.namespaceSelector }}
  namespaceSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  podMetricsEndpoints:
    {{- if .Values.podMonitor.endpoints }}
    {{- toYaml .Values.podMonitor.endpoints | nindent 4 }}
    {{- else }}
    - port: {{ .Values.podMonitor.port | default "metrics" }}
      path: {{ .Values.podMonitor.path | default "/metrics" }}
      interval: {{ .Values.podMonitor.interval | default "30s" }}
    {{- end }}
{{- end }}
{{- end }}
