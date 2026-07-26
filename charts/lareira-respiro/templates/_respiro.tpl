{{/*
lareira-respiro — adapter helpers.

respiro exposes ONE typed surface (`respiro.*`) and maps it onto each
already-shipped pleme-lib helper's NATIVE values contract by constructing a
per-helper sub-context: a shallow copy of the root context with `.Values`
swapped to the shape that helper reads. `.Chart` / `.Release` / `.Template` /
`.Capabilities` / `.Files` are preserved so the pleme-lib name / namespace /
labels helpers resolve against the real release identity.

This is pure WIRING — no new scaling/transport/homeostasis algebra. The helpers
do the work; these adapters only translate names.
*/}}

{{/*
lareira-respiro.consumerName — the consumer workload identity (the Deployment
that drains the stream + the KEDA/breathe target). Disambiguated by the chart
fullname so the consumer name is stable across the spine's stages.
*/}}
{{- define "lareira-respiro.consumerName" -}}
{{- printf "%s-consumer" (include "pleme-lib.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
lareira-respiro.vectorName — the INGEST Vector workload identity.
*/}}
{{- define "lareira-respiro.vectorName" -}}
{{- printf "%s-vector" (include "pleme-lib.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
lareira-respiro.ctx — build a helper sub-context. Args (dict):
  root   — the root chart context (`.`)
  values — the adapted .Values shape that the target helper reads
Returns a context with .Values replaced; identity fields preserved.
*/}}
{{- define "lareira-respiro.ctx" -}}
{{- $root := .root -}}
{{- $merged := merge (dict "Values" .values) (omit $root "Values") -}}
{{- $merged | toYaml -}}
{{- end -}}

{{/*
lareira-respiro.jetstreamCtx — adapt respiro.{stream,serverUrl} → the
pleme-lib.jetstream native `.Values.jetstream` contract (streams + consumers
maps). One workqueue stream + one pull consumer.
*/}}
{{- define "lareira-respiro.jetstreamValues" -}}
{{- $r := .Values.respiro -}}
{{- $s := $r.stream -}}
{{- $c := $s.consumer -}}
jetstream:
  enabled: true
  serverUrl: {{ $r.serverUrl | quote }}
  streams:
    {{ $s.name }}:
      subjects: {{ $s.subjects | toJson }}
      retention: {{ $s.retention | default "workqueue" }}
      storage: {{ $s.storage | default "file" }}
      replicas: 1
      maxBytes: {{ $s.maxBytes | default "5GB" | quote }}
      maxAge: {{ $s.maxAge | default "24h" | quote }}
      discard: old
  consumers:
    {{ $s.name }}:
      {{ $c.name }}:
        type: pull
        ackPolicy: explicit
        ackWait: {{ $c.ackWait | default "60s" | quote }}
        maxAckPending: {{ $c.maxAckPending | default 1 }}
        maxDeliver: {{ $c.maxDeliver | default 5 }}
        filterSubject: ""
        replayPolicy: instant
jetstreamInit:
  # PRE-install hook: the stream + durable consumer must exist BEFORE the main
  # resources are applied, because the KEDA ScaledObject (a waited main resource)
  # resolves its nats-jetstream trigger against the consumer. A post-install hook
  # deadlocks helm --wait (ScaledObject never Ready → wait hangs → hook never
  # runs). respiro's broker is an external pleme-nats release (dependsOn Ready),
  # so the broker is up at pre-install time.
  hookPhase: "pre-install,pre-upgrade"
{{- end -}}

{{/*
lareira-respiro.breathabilityValues — adapt respiro.{consumers,serverUrl,stream}
→ the pleme-lib.breathability native `.Values.breathability` contract. KEDA
ScaledObject, nats-jetstream trigger on stream lag, scale 0→N. The target is
the consumer Deployment.
*/}}
{{- define "lareira-respiro.breathabilityValues" -}}
{{- $r := .Values.respiro -}}
{{- $cons := $r.consumers -}}
{{- $s := $r.stream -}}
breathability:
  enabled: true
  targetKind: Deployment
  targetName: {{ include "lareira-respiro.consumerName" . }}
  min: {{ $cons.min | default 0 }}
  max: {{ $cons.max | default 8 }}
  cooldown: {{ $cons.cooldown | default 300 }}
  pollingInterval: {{ $cons.pollingInterval | default 15 }}
  trigger:
    type: nats-jetstream
    nats:
      serverURL: {{ $r.serverUrl | quote }}
      stream: {{ $s.name | quote }}
      consumer: {{ $s.consumer.name | quote }}
      lagThreshold: {{ $cons.lagThreshold | default 100 | quote }}
      activationLagThreshold: {{ $cons.activationLagThreshold | default 0 | quote }}
  hpa:
    enabled: false
{{- end -}}

{{/*
lareira-respiro.breatheValues — adapt respiro.breathe → the pleme-lib.breatheBand
native `.Values.breathe` contract, targeting the consumer Deployment (EXTERNAL
targetRef). BORN SHADOWED: `mode` defaults to shadow (dryRun is inert for this
band kind and never withheld anything — see the mode comment in the body).
*/}}
{{- define "lareira-respiro.breatheValues" -}}
{{- $b := .Values.respiro.breathe -}}
{{- $dryRun := $b.dryRun | default true -}}
{{- $setpoint := $b.setpoint | default 0.8 -}}
{{- /* mode — MUST be forwarded. This adapter RECONSTRUCTS the breathe dict
       field-by-field, so pleme-lib.breatheBand only ever sees keys named
       here: any key omitted is silently DROPPED, and its `{{- with $mem.mode }}`
       simply never fires. Before this line existed, a consumer setting
       respiro.breathe.mode got no error and no effect — the band was emitted
       with no mode at all and therefore BORN LIVE (dryRun is dead code for
       this band kind; promotion_mode() never reads it). Defaults to shadow so
       a band is born shadowed. Per-dimension memory.mode / cpu.mode win.
       If you add a new band field to pleme-lib, add it HERE too or it is
       dropped the same silent way. */ -}}
{{- $mode := $b.mode | default "shadow" -}}
{{- /* pleme-lib.breatheBand reads dryRun + setpoint + mode PER-DIMENSION (off
       the memory/cpu sub-dicts), so the respiro top-level dryRun/setpoint/mode
       are pushed down into both dimensions here. */ -}}
breathe:
  enabled: {{ $b.enabled }}
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "lareira-respiro.consumerName" . }}
  memory:
    enabled: {{ (default dict $b.memory).enabled | default false }}
    setpoint: {{ $setpoint }}
    floor: {{ (default dict $b.memory).floor | default "256Mi" }}
    ceiling: {{ (default dict $b.memory).ceiling | default "2Gi" }}
    dryRun: {{ $dryRun }}
    mode: {{ (default dict $b.memory).mode | default $mode }}
  cpu:
    enabled: {{ (default dict $b.cpu).enabled | default false }}
    setpoint: {{ $setpoint }}
    floor: {{ (default dict $b.cpu).floor | default "200m" }}
    ceiling: {{ (default dict $b.cpu).ceiling | default "2000m" }}
    dryRun: {{ $dryRun }}
    mode: {{ (default dict $b.cpu).mode | default $mode }}
{{- end -}}

{{/*
lareira-respiro.deliveryValues — adapt respiro.{sink,stream,serverUrl} → the
pleme-lib.delivery native `.Values.delivery` contract for the SINK stage's
durability semantics.
*/}}
{{- define "lareira-respiro.deliveryValues" -}}
{{- $r := .Values.respiro -}}
{{- $sink := $r.sink -}}
delivery:
  enabled: true
  tier: {{ (default dict $sink.delivery).tier | default "durable" }}
  nats:
    url: {{ $r.serverUrl | quote }}
    stream: {{ $r.stream.name | quote }}
    consumer: {{ $r.stream.consumer.name | quote }}
{{- end -}}
