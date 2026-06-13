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
    # ATTACH case (optional): scrape a DIFFERENT service/namespace than the
    # chart's own — e.g. lareira-observe attaching to pangea-operator. When
    # `target.selector` is set it (and `target.namespace`) are used instead of
    # the chart's own selectorLabels. `name` lets the CR ADOPT a specific
    # existing name (so a migration converges onto it rather than forking a CR).
    name: ""              # metadata.name override (default <fullname>)
    target:
      selector: {}        # matchLabels of the target Service
      namespace: ""       # namespaceSelector.matchNames (the target's namespace)
*/}}

{{- define "pleme-lib.vmServiceScrape" -}}
{{- if (.Values.vmScrape).enabled }}
{{- $target := (.Values.vmScrape).target }}
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMServiceScrape
metadata:
  name: {{ (.Values.vmScrape).name | default (include "pleme-lib.fullname" .) }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- $resAnnotations := include "pleme-lib.resourceAnnotations" . }}
  {{- if $resAnnotations }}
  annotations:
    {{- $resAnnotations | nindent 4 }}
  {{- end }}
spec:
  {{- if and $target $target.selector }}
  {{- with $target.namespace }}
  namespaceSelector:
    matchNames:
      - {{ . }}
  {{- end }}
  selector:
    matchLabels:
      {{- toYaml $target.selector | nindent 6 }}
  {{- else }}
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  {{- end }}
  endpoints:
    - port: {{ (.Values.vmScrape).port | default "http" }}
      path: {{ (.Values.vmScrape).path | default "/metrics" }}
      interval: {{ (.Values.vmScrape).interval | default "30s" }}
      scrapeTimeout: {{ (.Values.vmScrape).scrapeTimeout | default "10s" }}
{{- end }}
{{- end }}
