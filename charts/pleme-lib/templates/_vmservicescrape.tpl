{{/*
pleme-lib: vmServiceScrape named template — the VictoriaMetrics-native scrape.

Emits an operator.victoriametrics.com/v1beta1 VMServiceScrape mirroring
_servicemonitor.tpl's values surface, but under a `.Values.vmScrape` block.
This lets a chart target the VictoriaMetrics operator directly.

This is the native ALTERNATIVE, not a replacement: the existing
`pleme-lib.servicemonitor` (Prometheus-operator ServiceMonitor) still works via
vmagent's `selectAllByDefault`, which auto-converts ServiceMonitors. Use
`vmScrape` when a chart wants an explicit, first-class VMServiceScrape rather
than relying on the cross-CR conversion.

Usage in a chart's templates/vmservicescrape.yaml:
  {{- include "pleme-lib.vmServiceScrape" . }}

Values:
  vmScrape:
    enabled: false
    port: http            # service port NAME to scrape
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
*/}}

{{- define "pleme-lib.vmServiceScrape" -}}
{{- if (.Values.vmScrape).enabled }}
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMServiceScrape
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
    - port: {{ (.Values.vmScrape).port | default "http" }}
      path: {{ (.Values.vmScrape).path | default "/metrics" }}
      interval: {{ (.Values.vmScrape).interval | default "30s" }}
      scrapeTimeout: {{ (.Values.vmScrape).scrapeTimeout | default "10s" }}
{{- end }}
{{- end }}
