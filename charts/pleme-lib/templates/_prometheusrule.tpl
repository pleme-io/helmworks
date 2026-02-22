{{/*
pleme-lib: prometheusrule named template

PrometheusRule with raw groups passthrough.
*/}}

{{- define "pleme-lib.prometheusrule" -}}
{{- if (.Values.prometheusRules).enabled }}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    prometheus: main
spec:
  groups:
    {{- toYaml (.Values.prometheusRules).groups | nindent 4 }}
{{- end }}
{{- end }}
