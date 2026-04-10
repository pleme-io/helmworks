{{/*
pleme-lib.alerts — Observe slice (CIA).

Renders PrometheusRule with standard operational alerts that any service
should have. Toggle individual alert patterns via values.

Usage in a chart's templates/alerts.yaml:
  {{- include "pleme-lib.alerts" . }}

Values:
  alerts:
    enabled: true
    highErrorRate:
      enabled: true
      threshold: 5
      for: 5m
      severity: warning
    highLatency:
      enabled: true
      thresholdMs: 1000
      for: 5m
      severity: warning
    podRestarting:
      enabled: true
      threshold: 3
      for: 15m
      severity: critical
    highMemory:
      enabled: true
      threshold: 90
      for: 10m
      severity: warning
    custom: []
*/}}

{{- define "pleme-lib.alerts" -}}
{{- if .Values.alerts }}
{{- if .Values.alerts.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $labels := include "pleme-lib.labels" . }}
{{- $selectorLabels := include "pleme-lib.selectorLabels" . }}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ $fullname }}
  labels:
    {{- $labels | nindent 4 }}
spec:
  groups:
    - name: {{ $fullname }}.rules
      rules:
        {{/* ── Pod restarting alert ─────────────────────────────── */}}
        {{- if and .Values.alerts.podRestarting (default true .Values.alerts.podRestarting.enabled) }}
        - alert: {{ $fullname | title | replace "-" "" }}PodRestarting
          expr: |
            increase(kube_pod_container_status_restarts_total{
              namespace="{{ .Release.Namespace }}",
              pod=~"{{ $fullname }}.*"
            }[1h]) > {{ default 3 .Values.alerts.podRestarting.threshold }}
          for: {{ default "15m" .Values.alerts.podRestarting.for }}
          labels:
            severity: {{ default "critical" .Values.alerts.podRestarting.severity }}
            service: {{ $fullname }}
          annotations:
            summary: "{{ $fullname }} pod restarting frequently"
            description: "Pod {{`{{ $labels.pod }}`}} has restarted more than {{ default 3 .Values.alerts.podRestarting.threshold }} times in the last hour."
        {{- end }}

        {{/* ── High memory alert ───────────────────────────────── */}}
        {{- if and .Values.alerts.highMemory (default true .Values.alerts.highMemory.enabled) }}
        - alert: {{ $fullname | title | replace "-" "" }}HighMemory
          expr: |
            container_memory_working_set_bytes{
              namespace="{{ .Release.Namespace }}",
              pod=~"{{ $fullname }}.*",
              container!=""
            } / container_spec_memory_limit_bytes{
              namespace="{{ .Release.Namespace }}",
              pod=~"{{ $fullname }}.*",
              container!=""
            } * 100 > {{ default 90 .Values.alerts.highMemory.threshold }}
          for: {{ default "10m" .Values.alerts.highMemory.for }}
          labels:
            severity: {{ default "warning" .Values.alerts.highMemory.severity }}
            service: {{ $fullname }}
          annotations:
            summary: "{{ $fullname }} memory usage above {{ default 90 .Values.alerts.highMemory.threshold }}%"
            description: "Container {{`{{ $labels.container }}`}} in pod {{`{{ $labels.pod }}`}} is using {{`{{ $value | printf \"%.0f\" }}`}}% of its memory limit."
        {{- end }}

        {{/* ── High error rate alert ───────────────────────────── */}}
        {{- if and .Values.alerts.highErrorRate (default true .Values.alerts.highErrorRate.enabled) }}
        - alert: {{ $fullname | title | replace "-" "" }}HighErrorRate
          expr: |
            sum(rate(http_requests_total{
              namespace="{{ .Release.Namespace }}",
              job="{{ $fullname }}",
              code=~"5.."
            }[5m])) /
            sum(rate(http_requests_total{
              namespace="{{ .Release.Namespace }}",
              job="{{ $fullname }}"
            }[5m])) * 100 > {{ default 5 .Values.alerts.highErrorRate.threshold }}
          for: {{ default "5m" .Values.alerts.highErrorRate.for }}
          labels:
            severity: {{ default "warning" .Values.alerts.highErrorRate.severity }}
            service: {{ $fullname }}
          annotations:
            summary: "{{ $fullname }} error rate above {{ default 5 .Values.alerts.highErrorRate.threshold }}%"
            description: "Error rate is {{`{{ $value | printf \"%.1f\" }}`}}%."
        {{- end }}

        {{/* ── High latency alert ──────────────────────────────── */}}
        {{- if and .Values.alerts.highLatency (default true .Values.alerts.highLatency.enabled) }}
        - alert: {{ $fullname | title | replace "-" "" }}HighLatency
          expr: |
            histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{
              namespace="{{ .Release.Namespace }}",
              job="{{ $fullname }}"
            }[5m])) by (le)) * 1000 > {{ default 1000 .Values.alerts.highLatency.thresholdMs }}
          for: {{ default "5m" .Values.alerts.highLatency.for }}
          labels:
            severity: {{ default "warning" .Values.alerts.highLatency.severity }}
            service: {{ $fullname }}
          annotations:
            summary: "{{ $fullname }} p99 latency above {{ default 1000 .Values.alerts.highLatency.thresholdMs }}ms"
            description: "P99 latency is {{`{{ $value | printf \"%.0f\" }}`}}ms."
        {{- end }}

        {{/* ── Custom rules ────────────────────────────────────── */}}
        {{- range .Values.alerts.custom }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
{{- end }}
{{- end }}
{{- end }}
