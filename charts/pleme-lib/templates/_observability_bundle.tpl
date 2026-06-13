{{/*
pleme-lib.observabilityBundle — the maximally-abstracted observability composite.

ONE typed `.Values.observability` border fans out to the complete observability
surface for a workload: a metrics scrape CR + an alert-rules CR + an alert-route
CR + an optional Grafana dashboard ConfigMap — all through the existing pleme-lib
VM / ServiceMonitor helpers, behind a single `flavor` knob that selects the
VictoriaMetrics-native CRDs (default, for rio) or the Prometheus-operator CRDs
(SaaS clusters). This is generation-over-composition (Pillar 12) at the
observability layer: no chart hand-wires scrape+rule+route+dashboard separately.

  observability:
    flavor: vm                 # vm | prometheus
    scrape:                    # → VMServiceScrape (vm) / ServiceMonitor (prom)
      enabled: true
      port: metrics            # service port NAME
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
      name: ""                 # optional CR-name override (adopt an existing scrape)
      target: { selector: {}, namespace: "" }   # optional ATTACH override
    rules:                     # → VMRule (vm) / PrometheusRule (prom)
      enabled: true
      groups: [ ... ]          # pangea-GENERATED alert groups (persisted into values)
    alertmanagerConfig:        # → VMAlertmanagerConfig (vm) — ntfy routing
      enabled: false
      spec: { route: {...}, receivers: [...] }
    dashboard:                 # → ConfigMap (Grafana JSON, pangea-GENERATED)
      enabled: false
      name: dashboard
      json: "{...}"
      deploy: sidecar          # sidecar | provisioning | external

The scrape/rule/route are delegated to pleme-lib.{vmServiceScrape,vmRule,
vmAlertmanagerConfig,servicemonitor} by reconstructing the chart context with the
border remapped onto each helper's value path — so the bundle owns ZERO of their
logic; it is pure composition. Exactly ONE scrape CR renders (vm XOR prometheus)
→ no double-scrape.

Usage — the consuming chart's templates/observability.yaml is one line:
  {{- include "pleme-lib.observabilityBundle" . }}
*/}}

{{- define "pleme-lib.observabilityBundle" -}}
{{- $obs := .Values.observability | default dict -}}
{{- $flavor := $obs.flavor | default "vm" -}}
{{- $scrape := $obs.scrape | default dict -}}
{{- $rules := $obs.rules | default dict -}}
{{- $amc := $obs.alertmanagerConfig | default dict -}}
{{- $dash := $obs.dashboard | default dict -}}
{{/* augmented Values so the delegated helpers find their own value paths */}}
{{- $V := deepCopy .Values -}}
{{- $_ := set $V "vmScrape" $scrape -}}
{{- $_ := set $V "monitoring" $scrape -}}
{{- $_ := set $V "vm" (dict "rules" $rules "alertmanagerConfig" $amc) -}}
{{- $ctx := dict "Values" $V "Chart" .Chart "Release" .Release "Template" .Template "Capabilities" .Capabilities "Files" .Files -}}
{{- if eq $flavor "vm" -}}
{{- if $scrape.enabled }}
---
{{ include "pleme-lib.vmServiceScrape" $ctx -}}
{{- end }}
{{- if $rules.enabled }}
---
{{ include "pleme-lib.vmRule" $ctx -}}
{{- end }}
{{- if $amc.enabled }}
---
{{ include "pleme-lib.vmAlertmanagerConfig" $ctx -}}
{{- end }}
{{- else if eq $flavor "prometheus" -}}
{{- if $scrape.enabled }}
---
{{ include "pleme-lib.servicemonitor" $ctx -}}
{{- end }}
{{- if $rules.enabled }}
---
{{ include "pleme-lib._observabilityBundle.prometheusRule" $ctx -}}
{{- end }}
{{- else -}}
{{- fail (printf "pleme-lib.observabilityBundle: unknown flavor %q (want vm|prometheus)" $flavor) -}}
{{- end -}}
{{- if $dash.enabled }}
---
{{ include "pleme-lib._observabilityBundle.dashboard" . -}}
{{- end }}
{{- end -}}

{{/* internal: generic PrometheusRule from groups (prometheus flavor; no pleme-lib
   generic-groups helper exists — vmRule is the rio-native path). */}}
{{- define "pleme-lib._observabilityBundle.prometheusRule" -}}
{{- $r := .Values.vm.rules -}}
{{- if not $r.groups }}{{- fail "pleme-lib.observabilityBundle: rules.enabled requires non-empty `groups`" }}{{- end }}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  groups:
    {{- toYaml $r.groups | nindent 4 }}
{{- end -}}

{{/* internal: Grafana dashboard ConfigMap (pangea-generated JSON). The
   `grafana_dashboard` sidecar label is applied only for deploy: sidecar; for
   provisioning/external the ConfigMap is emitted unlabelled (mounted / pushed
   by another path). */}}
{{- define "pleme-lib._observabilityBundle.dashboard" -}}
{{- $d := .Values.observability.dashboard -}}
{{/* the Grafana JSON comes from `json` (inline) OR `file` (a chart path read via
   .Files.Get — for large pangea-generated dashboards that would bloat values). */}}
{{- $json := $d.json -}}
{{- if and (not $json) $d.file -}}{{- $json = .Files.Get $d.file -}}{{- end -}}
{{- if not $json }}{{- fail "pleme-lib.observabilityBundle: dashboard.enabled requires `json` (inline) or `file` (a chart path)" }}{{- end }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "pleme-lib.fullname" . }}-dashboard
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    {{- if eq ($d.deploy | default "sidecar") "sidecar" }}
    grafana_dashboard: "1"
    {{- end }}
data:
  {{ $d.name | default "dashboard" }}.json: |
    {{- $json | nindent 4 }}
{{- end -}}
