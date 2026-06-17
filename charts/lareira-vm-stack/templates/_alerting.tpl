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
{{- /* ntfy query suffix: per-severity priority + (optional) message templating.
       The title/message Go-templates live in values (literal, not Helm-processed)
       and are urlquery-encoded into the webhook URL — ntfy parses the Alertmanager
       JSON body and evaluates them, so phone notifications read as
       "<alertname>" / "<summary>" instead of a raw JSON blob. */ -}}
{{- $tpl := "" -}}
{{- if (($n.template).enabled) -}}
{{- $tpl = printf "&template=1&title=%s&message=%s" (urlquery $n.template.title) (urlquery $n.template.message) -}}
{{- end -}}
{{- /* HARDENING: when ntfy auth is on, Alertmanager authenticates to ntfy with
       HTTP basic_auth (the password from a mounted Secret), so the public ntfy
       endpoint requires a credential to publish — not open. $auth is appended
       after each webhook's send_resolved as an indented http_config block. */ -}}
{{- $auth := "" -}}
{{- if (($n.auth).enabled) -}}
{{- $auth = printf "\n        http_config:\n          basic_auth:\n            username: %s\n            password_file: %s" $n.auth.username ($n.auth.passwordFile | default "/etc/vm/secrets/ntfy-auth/password") -}}
{{- end -}}
receivers:
  - name: rio-critical
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.critical }}?priority=urgent&tags=rotating_light{{ $tpl }}
        send_resolved: true{{ $auth }}
  - name: rio-warning
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.warning }}?priority=high&tags=warning{{ $tpl }}
        send_resolved: true{{ $auth }}
  - name: rio-info
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.info }}?priority=default{{ $tpl }}
        send_resolved: false{{ $auth }}
  - name: rio-heartbeat
    webhook_configs:
      - url: {{ $n.baseUrl }}/{{ $n.topics.heartbeat }}?priority=min&tags=heartbeat{{ $tpl }}
        send_resolved: false{{ $auth }}
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
