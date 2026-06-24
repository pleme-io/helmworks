{{/*
pleme-lib.vectorConfig — typed Vector configuration emitter.

The ONE net-new code surface of the respiro "breathing pipeline" primitive:
a typed renderer that builds a Vector config (the standard top-level
`data_dir` / `api` / `sources` / `transforms` / `sinks` map form Vector
loads) from a typed values block and serializes it with `toYaml`.

★★ TYPED EMISSION (org CLAUDE.md): the config is assembled as a Helm dict
and rendered through a SINGLE `toYaml`. There is NO string-concatenation of
config syntax anywhere — every byte of the emitted config is the
deterministic serialization of a structured value. Adding a source/sink kind
is adding a typed arm to the dict, never another printf.

────────────────────────────────────────────────────────────────────
USAGE
────────────────────────────────────────────────────────────────────

This template returns the rendered Vector config YAML as a STRING. A
consumer embeds it in a ConfigMap `data` key:

  data:
    vector.yaml: |
      {{- include "pleme-lib.vectorConfig" (dict "ingest" .Values.respiro.ingest "stream" .Values.respiro.stream "serverUrl" .Values.respiro.serverUrl) | nindent 4 }}

Args (passed via `dict`):
  ingest    — the typed ingest block (source.kind + per-kind config,
              transforms list, sink stream/subject). REQUIRED.
  stream    — the JetStream stream block (used only for the NATS sink
              subject default when ingest.sink is unset). OPTIONAL.
  serverUrl — the NATS server URL the `nats` sink publishes to. REQUIRED
              for the nats sink (the only A0 sink).

────────────────────────────────────────────────────────────────────
SOURCES (A0)
────────────────────────────────────────────────────────────────────

  source.kind ∈ { kubernetes_logs | http | socket }

  kubernetes_logs:
    extraLabelSelector: ""        # Vector `extra_label_selector`
  http:                           # (http_server source)
    address: "0.0.0.0:8080"
    encoding: json                # text | json | ndjson | bytes
  socket:
    address: "0.0.0.0:9000"
    mode: tcp                     # tcp | udp | unix

  source.kind = s3 is a LATER MILESTONE — a typed slot exists below and
  fail()s with a clear message so the gap surfaces mechanically rather
  than emitting a silently-wrong config.

────────────────────────────────────────────────────────────────────
SINK (A0)
────────────────────────────────────────────────────────────────────

  The terminal sink of the INGEST stage is always the Vector `nats` sink
  (transport hand-off into JetStream). The downstream consumer egress
  (vlogs|nats) is a SEPARATE stage owned by sink.yaml — not this emitter.
*/}}

{{- define "pleme-lib.vectorConfig" -}}
{{- $ingest := .ingest | default dict -}}
{{- $stream := .stream | default dict -}}
{{- $serverUrl := .serverUrl | default "nats://pleme-nats.nats.svc:4222" -}}
{{- $source := $ingest.source | default dict -}}
{{- $kind := $source.kind | default "kubernetes_logs" -}}
{{- $sink := $ingest.sink | default dict -}}

{{- /* ── Build the source value (typed dispatch on kind) ───────────── */ -}}
{{- $sourceVal := dict -}}
{{- if eq $kind "kubernetes_logs" -}}
  {{- $k := $source.kubernetes_logs | default dict -}}
  {{- $sourceVal = dict "type" "kubernetes_logs" -}}
  {{- with $k.extraLabelSelector -}}
    {{- $_ := set $sourceVal "extra_label_selector" . -}}
  {{- end -}}
{{- else if eq $kind "http" -}}
  {{- $k := $source.http | default dict -}}
  {{- $sourceVal = dict
        "type" "http_server"
        "address" ($k.address | default "0.0.0.0:8080")
        "encoding" ($k.encoding | default "json") -}}
{{- else if eq $kind "socket" -}}
  {{- $k := $source.socket | default dict -}}
  {{- $sourceVal = dict
        "type" "socket"
        "address" ($k.address | default "0.0.0.0:9000")
        "mode" ($k.mode | default "tcp") -}}
{{- else if eq $kind "s3" -}}
  {{- fail "pleme-lib.vectorConfig: source.kind=s3 is a later milestone (A1+), not yet implemented — use kubernetes_logs | http | socket for A0" -}}
{{- else -}}
  {{- fail (printf "pleme-lib.vectorConfig: unknown source.kind %q — supported A0 kinds are kubernetes_logs | http | socket (s3 is a later milestone)" $kind) -}}
{{- end -}}

{{- /* ── Wire the source → transforms passthrough → sink input chain ── */ -}}
{{- $transforms := $ingest.transforms | default list -}}
{{- $sourceInputs := list "respiro_source" -}}
{{- $transformsMap := dict -}}
{{- $lastOutput := "respiro_source" -}}
{{- range $i, $t := $transforms -}}
  {{- $tname := printf "respiro_transform_%d" $i -}}
  {{- /* Each transform is a typed Vector transform dict; we set its `inputs`
         to the previous stage so the chain is deterministic. Passthrough:
         the operator supplies the transform body verbatim (type + config). */ -}}
  {{- $tcopy := deepCopy $t -}}
  {{- $_ := set $tcopy "inputs" (list $lastOutput) -}}
  {{- $_ := set $transformsMap $tname $tcopy -}}
  {{- $lastOutput = $tname -}}
{{- end -}}

{{- /* ── Build the nats sink (the transport hand-off) ──────────────── */ -}}
{{- $subject := $sink.subject | default (printf "%s.>" (lower ($stream.name | default "audit"))) -}}
{{- $sinkVal := dict
      "type" "nats"
      "inputs" (list $lastOutput)
      "url" $serverUrl
      "subject" $subject
      "encoding" (dict "codec" "json") -}}

{{- /* ── Assemble the whole config as ONE typed dict, then toYaml ───── */ -}}
{{- $cfg := dict
      "data_dir" "/vector-data-dir"
      "api" (dict "enabled" true "address" "0.0.0.0:8686")
      "sources" (dict "respiro_source" $sourceVal)
      "sinks" (dict "respiro_nats" $sinkVal) -}}
{{- if $transformsMap -}}
  {{- $_ := set $cfg "transforms" $transformsMap -}}
{{- end -}}
{{- toYaml $cfg -}}
{{- end -}}
