{{/*
pleme-lib.routing — the destination-routing seam.

ONE `routing.destination` enum drives every routing surface, authored ONCE here
so alert charts (lareira-pangea-alerts) and the respiro OBSERVE stage never fork
the mapping:

  pleme-lib.routing.destination   → validate the enum + echo it (fail on unknown)
  pleme-lib.routing.labels        → the `dest: <v>` label block (stamped on rules/CRs)
  pleme-lib.routing.receiverName  → the Alertmanager receiver name for a destination
  pleme-lib.routing.receiver      → the Alertmanager receiver object for a destination

Destination contract — TWO ARMS, and the allowed SET is caller-declared.
The enum stays CLOSED (a typo must fail, not route nowhere), but its membership
is a value rather than a literal in this file: the reusable artifact is the RULE
and the two arms, never the catalog of who we happen to send to.

  luis            — the NTFY arm. routing.ntfyTopic + routing.ntfyUrl are
                    REQUIRED; an empty ntfyTopic fail()s (an alert with nowhere
                    to go is a bug, not a silent no-op). Always permitted.
  <any declared>  — the WEBHOOK arm, INERT-IF-EMPTY. Emits a named receiver
                    whose webhookConfigs is `[]` until routing.webhookUrl is
                    wired (build-but-configure-off — the `dest: <v>` seam exists
                    and matches, the sink is a later wiring).

  routing.destinations — the caller's declared webhook destination names.
                    Defaults to ["partner"]. A consumer that routes somewhere
                    else declares that name in ITS OWN values; this library
                    never learns who the downstream is.
                    NOTE (Helm law): a list-typed DEFAULT is discarded wholesale
                    by any consumer that sets the list — declare the full set,
                    not the delta.

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
{{- $allowed := concat (list "luis") (((.routing | default dict).destinations) | default (list "partner")) -}}
{{- if not $dest -}}
{{- fail (printf "pleme-lib.routing (%s): routing.destination is required — one of %s" $ctx (join "|" $allowed)) -}}
{{- end -}}
{{- if not (has $dest $allowed) -}}
{{- fail (printf "pleme-lib.routing (%s): unknown routing.destination %q — must be one of %s (declare additional names in routing.destinations)" $ctx $dest (join "|" $allowed)) -}}
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
