{{- /*
Alerting architecture helpers — the configurable push pipeline.

`lareira-vm-stack.alertmanagerConfig` renders the Alertmanager `configRawYaml`
from `.Values.alerting`, switching on `alerting.receiver`:
  - blackhole : alerts fire but go nowhere (the silent default).
  - ntfy      : the full severity → ntfy-topic push architecture.

This is THE toggle: flipping `alerting.receiver` between the two re-renders the
whole receiver/route tree. Everything is values-driven (ntfy base URL, the
per-severity topic names, the grouping cadences), so the architecture is one
configurable unit of the observability stack.
*/ -}}
{{- define "lareira-vm-stack.alertmanagerConfig" -}}
{{- $a := .Values.alerting -}}
{{- if eq $a.receiver "ntfy" -}}
{{- $n := $a.ntfy -}}
receivers:
  - name: rio-critical
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.critical }}
        send_resolved: true
  - name: rio-warning
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.warning }}
        send_resolved: true
  - name: rio-info
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.info }}
        send_resolved: false
  - name: rio-heartbeat
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.heartbeat }}
        send_resolved: false
route:
  receiver: rio-warning
  group_by: {{ $a.route.groupBy | toJson }}
  group_wait: {{ $a.route.groupWait }}
  group_interval: {{ $a.route.groupInterval }}
  repeat_interval: {{ $a.route.repeatInterval }}
  routes:
    - matchers: ['severity="critical"']
      receiver: rio-critical
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1h
    - matchers: ['severity="info"']
      receiver: rio-info
      group_wait: 5m
      group_interval: 30m
      repeat_interval: 24h
    - matchers: ['severity="heartbeat"']
      receiver: rio-heartbeat
      group_wait: 0s
      group_interval: {{ $a.heartbeatInterval | default "6h" }}
      repeat_interval: {{ $a.heartbeatInterval | default "6h" }}
{{- else -}}
receivers:
  - name: blackhole
route:
  receiver: blackhole
  group_by: [namespace, alertname]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
{{- end -}}
{{- end -}}
