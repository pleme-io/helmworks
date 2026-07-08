{{/*
pleme-lib.routing — the destination-routing seam (luis | akeyless | 2f).

ONE `routing.destination` enum drives every routing surface, authored ONCE here
so alert charts (lareira-pangea-alerts) and the respiro OBSERVE stage never fork
the mapping:

  pleme-lib.routing.destination   → validate the enum + echo it (fail on unknown)
  pleme-lib.routing.labels        → the `dest: <v>` label block (stamped on rules/CRs)
  pleme-lib.routing.receiverName  → the Alertmanager receiver name for a destination
  pleme-lib.routing.receiver      → the Alertmanager receiver object for a destination

Destination contract:
  luis     — WIRED. Routes to ntfy. routing.ntfyTopic + routing.ntfyUrl are
             REQUIRED; an empty ntfyTopic fail()s (a luis alert with nowhere to
             go is a bug, not a silent no-op).
  akeyless — INERT-IF-EMPTY. Emits a named receiver whose webhookConfigs is `[]`
             until routing.webhookUrl is wired (build-but-configure-off — the
             `dest: akeyless` seam exists and matches, the sink is a later wiring).
  2f       — INERT-IF-EMPTY. Same seam as akeyless, a distinct receiver name.

Call convention — EVERY helper takes ONE dict argument:
  (dict "destination" <string> "routing" <dict> "ctx" <string>)
    destination — the enum value (required)
    routing     — the per-destination config dict (ntfyTopic/ntfyUrl/webhookUrl/…),
                  only consulted by pleme-lib.routing.receiver
    ctx         — a caller label woven into fail() messages (chart / alert name)
*/}}

{{/* ── enum guard: validate + echo the destination ─────────────────────── */}}
{{- define "pleme-lib.routing.destination" -}}
{{- $dest := .destination -}}
{{- $ctx := .ctx | default "routing" -}}
{{- if not $dest -}}
{{- fail (printf "pleme-lib.routing (%s): routing.destination is required — one of luis|akeyless|2f" $ctx) -}}
{{- end -}}
{{- if not (has $dest (list "luis" "akeyless" "2f")) -}}
{{- fail (printf "pleme-lib.routing (%s): unknown routing.destination %q — must be one of luis|akeyless|2f" $ctx $dest) -}}
{{- end -}}
{{- $dest -}}
{{- end -}}

{{/* ── the `dest: <v>` label block (validated) ─────────────────────────── */}}
{{- define "pleme-lib.routing.labels" -}}
{{- $dest := include "pleme-lib.routing.destination" . -}}
dest: {{ $dest }}
{{- end -}}

{{/* ── the Alertmanager receiver name for a destination ────────────────── */}}
{{- define "pleme-lib.routing.receiverName" -}}
{{- $dest := include "pleme-lib.routing.destination" . -}}
pleme-routing-{{ $dest }}
{{- end -}}

{{/* ── the Alertmanager receiver object for a destination ──────────────── */}}
{{- define "pleme-lib.routing.receiver" -}}
{{- $dest := include "pleme-lib.routing.destination" . -}}
{{- $r := .routing | default dict -}}
{{- $ctx := .ctx | default "routing" -}}
{{- $name := include "pleme-lib.routing.receiverName" . -}}
{{- $sendResolved := $r.sendResolved | default true -}}
{{- if eq $dest "luis" -}}
{{- $topic := $r.ntfyTopic | default "" -}}
{{- if eq $topic "" -}}
{{- fail (printf "pleme-lib.routing (%s): destination=luis requires routing.ntfyTopic (the ntfy topic alerts route to)" $ctx) -}}
{{- end -}}
{{- $url := $r.ntfyUrl | default "" -}}
{{- if eq $url "" -}}
{{- fail (printf "pleme-lib.routing (%s): destination=luis requires routing.ntfyUrl (the ntfy webhook URL alerts POST to)" $ctx) -}}
{{- end -}}
- name: {{ $name }}
  webhookConfigs:
    - url: {{ $url | quote }}
      sendResolved: {{ $sendResolved }}
{{- else -}}
{{- $url := $r.webhookUrl | default "" -}}
- name: {{ $name }}
  webhookConfigs:
{{- if eq $url "" }} []
{{- else }}
    - url: {{ $url | quote }}
      sendResolved: {{ $sendResolved }}
{{- end -}}
{{- end -}}
{{- end -}}
