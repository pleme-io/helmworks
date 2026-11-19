{{/*
pleme-vector helpers — delegates to pleme-lib
*/}}

{{- define "pleme-vector.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-vector.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{/*
Build the list of enabled source names in order (comma-separated, no spaces).
Used for faucet level 1 sink inputs.
*/}}
{{/*
Returns "true" when at least one sink that consumes the LOG chain is enabled.

★ Without this, `sink.loki.enabled=false` silently discarded 100% of logs: the
whole chain still rendered, victoria_logs_msg became terminal with no consumer,
and Vector reported one warning and exited 0. The highest-severity finding of
the toggle sweep, and completely invisible to an exit-code oracle.
*/}}
{{- define "pleme-vector.hasLogSink" -}}
{{- $s := .Values.sink -}}
{{- /* `dig` rather than direct field access: a values file that omits a sink
       block entirely (several examples do) would otherwise blow up on a nil
       map. The key names are the real ones -- `file`, not `file_output`;
       getting that wrong is how this helper first broke agent-aggregator. */ -}}
{{- if or (dig "loki" "enabled" false $s) (dig "file" "enabled" false $s)
        (dig "console_debug" "enabled" false $s) (dig "blackhole" "enabled" false $s)
        (dig "datadog" "enabled" false $s) (dig "splunk_hec" "enabled" false $s)
        (dig "analytics" "enabled" false $s) (gt (len (default dict $s.custom)) 0)
        (dig "vector" "enabled" false $s)
        .Values.delivery_dlq.enabled
        (eq (include "pleme-vector.isProducer" .) "true")
        (gt (len (default list .Values.processing.vector_sinks)) 0)
        .Values.multi_tenant.enabled
        (gt (len (default dict .Values.transform.custom)) 0)
        .Values.processing.tap.enabled
        .Values.fleetShipping.enabled -}}true{{- end -}}
{{- end -}}

{{- define "pleme-vector.sourceNames" -}}
{{- /* In consumer mode the sources are nats_logs / nats_metrics /
       internal_metrics -- NOT the ingestion.* set, which is not emitted at all.
       Without this gate, faucet level 1 in consumer mode built its sink inputs
       from ingestion toggles and named components that do not exist. */ -}}
{{- if eq (include "pleme-vector.isConsumer" .) "true" -}}
  {{- print "nats_logs,nats_metrics,internal_metrics" -}}
{{- else -}}
{{- $sources := list -}}
{{- if .Values.ingestion.kubernetes_logs.enabled -}}
  {{- $sources = append $sources "kubernetes_logs" -}}
{{- end -}}
{{- if .Values.ingestion.journald.enabled -}}
  {{- $sources = append $sources "journald" -}}
{{- end -}}
{{- if .Values.ingestion.internal_metrics.enabled -}}
  {{- $sources = append $sources "internal_metrics" -}}
{{- end -}}
{{- if .Values.ingestion.statsd.enabled -}}
  {{- $sources = append $sources "statsd" -}}
{{- end -}}
{{- if .Values.ingestion.hubble.enabled -}}
  {{- $sources = append $sources "hubble_flows" -}}
{{- end -}}
{{- /* configmap.yaml emits ONE source per target, named prometheus_scrape_<i>.
       The unindexed literal never matches a component, so every consumer of
       sourceNames got a dangling input. `metricsInputs` below already ranged
       correctly -- this helper was simply never updated when the range loop
       landed. An `enabled: true` with `targets: []` contributes nothing, which
       is right: no source is rendered either. */ -}}
{{- if .Values.ingestion.prometheus_scrape.enabled -}}
  {{- range $i, $target := .Values.ingestion.prometheus_scrape.targets -}}
    {{- $sources = append $sources (printf "prometheus_scrape_%d" $i) -}}
  {{- end -}}
{{- end -}}
{{- if .Values.ingestion.http_server.enabled -}}
  {{- $sources = append $sources "http_server" -}}
{{- end -}}
{{- if .Values.ingestion.kubernetes_events.enabled -}}
  {{- $sources = append $sources "kubernetes_events" -}}
{{- end -}}
{{- if .Values.ingestion.burst_forge_http.enabled -}}
  {{- $sources = append $sources "burst_forge_http" -}}
{{- end -}}
{{- /* See logSourceNames: without these the exec sources have no consumers
       and their data is collected and discarded. */ -}}
{{- if .Values.ingestion.pprof_capture.enabled -}}
  {{- range .Values.ingestion.pprof_capture.targets -}}
    {{- $sources = append $sources (printf "pprof_%s" .name) -}}
  {{- end -}}
{{- end -}}
{{- if .Values.ingestion.kubernetes_events_raw.enabled -}}
  {{- $sources = append $sources "kubernetes_events_raw" -}}
{{- end -}}
{{- if .Values.processing.vector_source.enabled -}}
  {{- $sources = append $sources "vector_source" -}}
{{- end -}}
{{- join "," $sources -}}
{{- end -}}
{{- end -}}

{{/*
Build the list of log source names (excludes metrics-only sources).
Used as inputs for log transforms. Comma+space separated.
*/}}
{{- define "pleme-vector.logSourceNames" -}}
{{- $sources := list -}}
{{- if .Values.ingestion.kubernetes_logs.enabled -}}
  {{- $sources = append $sources "kubernetes_logs" -}}
{{- end -}}
{{- if .Values.ingestion.journald.enabled -}}
  {{- $sources = append $sources "journald" -}}
{{- end -}}
{{- if .Values.ingestion.hubble.enabled -}}
  {{- $sources = append $sources "hubble_flows" -}}
{{- end -}}
{{- if .Values.ingestion.http_server.enabled -}}
  {{- $sources = append $sources "http_server" -}}
{{- end -}}
{{- /* exec-based log sources. Without these entries they are emitted as
       sources, referenced by NO downstream inputs, and their data is
       collected and silently discarded -- Vector says so
       ("~ Source X has no consumers") but only as a WARNING, so the config
       validates and the loss is invisible. Measured on the LIVE scale-test
       values, which enable kubernetes_events_raw and two real pprof gateway
       targets. */ -}}
{{- if .Values.ingestion.pprof_capture.enabled -}}
  {{- range .Values.ingestion.pprof_capture.targets -}}
    {{- $sources = append $sources (printf "pprof_%s" .name) -}}
  {{- end -}}
{{- end -}}
{{- if .Values.ingestion.kubernetes_events_raw.enabled -}}
  {{- $sources = append $sources "kubernetes_events_raw" -}}
{{- end -}}
{{- /* The remaining LOG sources. Each was emitted and consumed by nothing --
       `~ Source "X" has no consumers`, a warning, exit 0 -- so enabling any of
       them ingested into a void while the config validated clean. These are
       log-shaped (HEC events, HTTP bodies, OTLP logs, operator-supplied), so
       they belong in the log chain like any other. */ -}}
{{- if .Values.ingestion.splunk_hec.enabled -}}
  {{- $sources = append $sources "splunk_hec" -}}
{{- end -}}
{{- if .Values.ingestion.burst_forge_http.enabled -}}
  {{- $sources = append $sources "burst_forge_http" -}}
{{- end -}}
{{- /* `.logs`, not the bare name: Vector's opentelemetry source has NAMED
       outputs (logs / traces) and no default port, so `- opentelemetry` never
       matches a component. The log chain wants the log stream. */ -}}
{{- if .Values.ingestion_opentelemetry.enabled -}}
  {{- $sources = append $sources "opentelemetry.logs" -}}
{{- end -}}
{{- /* ingestion.custom is a raw toYaml passthrough, but its component NAMES
       are knowable -- they are the map keys -- so they can be wired like any
       other source instead of being left dangling. */ -}}
{{- range $name, $cfg := .Values.ingestion.custom -}}
  {{- $sources = append $sources $name -}}
{{- end -}}
{{- if .Values.processing.vector_source.enabled -}}
  {{- $sources = append $sources "vector_source" -}}
{{- end -}}
{{- join ", " $sources -}}
{{- end -}}

{{/*
Resolve the final transform name in the log-processing chain.
Returns empty string when no log sources exist (deployment mode without kubernetes_logs).
Sinks that consume logs should use this as their input via {{- with }} guard.
*/}}
{{/*
★ THE LOG CHAIN ORDER, WRITTEN ONCE.

This list is the single source of truth for the order of the log-transform
chain. Before it existed the order was written TWICE -- once as the cascade in
lastLogTransform, and again as a hand-rolled "hardcoded prior" chain inside
each transform's `inputs:` -- and the two were free to disagree. They did, and
the disagreements were not cosmetic:

  * akeyless_event_detect read lastLogTransform (the chain TAIL) while sitting
    in the middle of the chain, producing a CYCLE that killed 6 of 17 examples.
  * akeyless_gw/wh_log_parse were absent from the cascade, so they enriched
    events that nothing downstream consumed -- silent, exit 0.

Both are the same bug: a stage's prior must be derived from the order, not
restated beside it. `logChainPrior` derives it, so a new stage is one entry
here and cannot desynchronise.

Pass: (dict "stage" "<name>" "ctx" $). Returns the nearest ENABLED stage before
`stage`, or the source list when none precedes it. Pass stage "" for the tail.
*/}}
{{- define "pleme-vector.logChainOrder" -}}
k8s_enrich,json_parse,log_level_normalize,akeyless_event_detect,akeyless_gw_log_parse,akeyless_wh_log_parse,experiment_tag,product_detect
{{- end -}}

{{- define "pleme-vector.logChainEnabled" -}}
{{- $ctx := .ctx -}}{{- $stage := .stage -}}
{{- $t := $ctx.Values.transform -}}
{{- if eq $stage "k8s_enrich" -}}{{ $t.kubernetes_metadata.enabled }}
{{- else if eq $stage "json_parse" -}}{{ $t.json_parse.enabled }}
{{- else if eq $stage "log_level_normalize" -}}{{ $t.log_level_normalize.enabled }}
{{- else if eq $stage "akeyless_event_detect" -}}{{ $t.akeyless_event_detect.enabled }}
{{- else if eq $stage "akeyless_gw_log_parse" -}}{{ $t.akeyless_gw_log_parse.enabled }}
{{- else if eq $stage "akeyless_wh_log_parse" -}}{{ $t.akeyless_wh_log_parse.enabled }}
{{- else if eq $stage "experiment_tag" -}}{{ $t.experiment_tag.enabled }}
{{- else if eq $stage "product_detect" -}}{{ $t.product_detect.enabled }}
{{- else -}}false{{- end -}}
{{- end -}}

{{- define "pleme-vector.logChainPrior" -}}
{{- $ctx := .ctx -}}{{- $stage := .stage -}}
{{- $order := splitList "," (include "pleme-vector.logChainOrder" .) -}}
{{- $prior := "" -}}
{{- range $order -}}
  {{- if and (ne $stage "") (eq . $stage) -}}
    {{- /* stop: everything after this is downstream of us */ -}}
  {{- else if eq (include "pleme-vector.logChainPrior.stop" (dict "order" $order "stage" $stage "at" .)) "true" -}}
    {{- if eq (include "pleme-vector.logChainEnabled" (dict "stage" . "ctx" $ctx)) "true" -}}
      {{- $prior = . -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if eq $prior "" -}}
  {{- include "pleme-vector.logSourceNames" $ctx -}}
{{- else -}}
  {{- $prior -}}
{{- end -}}
{{- end -}}

{{/* "true" while `at` is strictly before `stage` in `order` (or stage is ""). */}}
{{- define "pleme-vector.logChainPrior.stop" -}}
{{- $order := .order -}}{{- $stage := .stage -}}{{- $at := .at -}}
{{- if eq $stage "" -}}true
{{- else -}}
  {{- $si := -1 -}}{{- $ai := -1 -}}
  {{- range $i, $s := $order -}}
    {{- if eq $s $stage -}}{{- $si = $i -}}{{- end -}}
    {{- if eq $s $at -}}{{- $ai = $i -}}{{- end -}}
  {{- end -}}
  {{- if lt $ai $si -}}true{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pleme-vector.lastLogTransform" -}}
{{- $logSources := include "pleme-vector.logSourceNames" . -}}
{{- if eq $logSources "" -}}
  {{- /* No log sources — entire log chain is empty */ -}}
{{- else -}}
  {{- $last := "" -}}
  {{- if .Values.transform.kubernetes_metadata.enabled -}}
    {{- $last = "k8s_enrich" -}}
  {{- end -}}
  {{- if .Values.transform.json_parse.enabled -}}
    {{- $last = "json_parse" -}}
  {{- end -}}
  {{- if .Values.transform.log_level_normalize.enabled -}}
    {{- $last = "log_level_normalize" -}}
  {{- end -}}
  {{- if .Values.transform.akeyless_event_detect.enabled -}}
    {{- $last = "akeyless_event_detect" -}}
  {{- end -}}
  {{- /* Both akeyless parsers were TERMINAL: they ran, enriched the event, and
         nothing consumed the result. Adding them to the cascade is what makes
         their output reach the sinks. Both take hardcoded-PRIOR inputs, which
         is what keeps that from being a self-reference. */ -}}
  {{- if .Values.transform.akeyless_gw_log_parse.enabled -}}
    {{- $last = "akeyless_gw_log_parse" -}}
  {{- end -}}
  {{- if .Values.transform.akeyless_wh_log_parse.enabled -}}
    {{- $last = "akeyless_wh_log_parse" -}}
  {{- end -}}
  {{- if .Values.transform.experiment_tag.enabled -}}
    {{- $last = "experiment_tag" -}}
  {{- end -}}
  {{- if .Values.transform.product_detect.enabled -}}
    {{- $last = "product_detect" -}}
  {{- end -}}
  {{- /* `schema_normalize` was REMOVED here (and from values.yaml). It was a
         PHANTOM: this cascade returned the name, but configmap.yaml never
         emitted a matching transform -- it arrived in the chart's first commit
         as a knob plus this branch, with no body, and was never implemented.
         Setting it produced:
           x Input "schema_normalize" for transform "victoria_logs_msg"
             doesn't match any components
         so nobody can have been running it successfully. Emitting a real
         transform instead would mean inventing an OTel semantic-conventions
         mapping from scratch -- new feature work on a chart scheduled for
         deletion, and it would have to guess the field mapping.
         Cost, stated: `helm show values` stops advertising OTel
         normalization. A leftover `transform.schema_normalize.enabled: true`
         in an operator's values becomes an inert ignored key (there is no
         values.schema.json), so their release starts working rather than
         breaking. */ -}}
  {{- if eq $last "" -}}
    {{- $logSources -}}
  {{- else -}}
    {{- $last -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
The log-pipeline output BEFORE the terminal victoria_logs_msg remap —
lastLogTransform + exactly_once_id if enabled. This is what victoria_logs_msg
itself consumes (using finalOutput here would be a self-reference).
*/}}
{{/*
The chain tail AFTER filtering.

★ This rung did not exist, and its absence made `transform.filter` a NO-OP.
`filter_events` consumed lastLogTransform, but nothing consumed
`filter_events` -- so the filter ran, produced a filtered stream, and that
stream went nowhere while the UNFILTERED stream continued to every sink.
Vector reported it as `~ Transform "filter_events" has no consumers`: a
warning, exit 0. An operator would see a validated config, believe their
events were being filtered, and be wrong.

filter_events itself still takes lastLogTransform (the PRE-filter tail), which
is what keeps this from becoming a self-reference -- the same trap that made
akeyless_event_detect cyclic.
*/}}
{{- define "pleme-vector.postFilterOutput" -}}
{{- $logSources := include "pleme-vector.logSourceNames" . -}}
{{- if and .Values.transform.filter.enabled (ne $logSources "") -}}
filter_events
{{- else -}}
  {{- include "pleme-vector.lastLogTransform" . -}}
{{- end -}}
{{- end -}}

{{- define "pleme-vector.preMsgOutput" -}}
{{- if .Values.delivery_exactly_once.enabled -}}
exactly_once_id
{{- else -}}
  {{- include "pleme-vector.postFilterOutput" . -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the absolute final pipeline output — preMsgOutput, then the terminal
victoria_logs_msg remap when enabled (and log sources exist). This is what
sinks, traffic ops, and taps should use as their input. victoria_logs_msg is
terminal so EVERY log sink gets a guaranteed `_msg` (harmless for non-VLogs).
*/}}
{{- define "pleme-vector.finalOutput" -}}
{{- $logSources := include "pleme-vector.logSourceNames" . -}}
{{- if and .Values.transform.victoria_logs_msg.enabled (ne $logSources "") -}}
victoria_logs_msg
{{- else -}}
  {{- include "pleme-vector.preMsgOutput" . -}}
{{- end -}}
{{- end -}}

{{/*
Render VictoriaMetrics input list (metrics-only sources, no log pipeline).
Used by both tiered and non-tiered sink paths.
*/}}
{{- define "pleme-vector.metricsInputs" -}}
{{- /* internal_metrics is now GATED rather than unconditional: it was the only
       hardcoded entry, so disabling that source while leaving a metrics sink on
       produced `Input "internal_metrics" ... doesn't match any components`. */ -}}
{{- if .Values.ingestion.internal_metrics.enabled }}
- internal_metrics
{{- end }}
{{- if .Values.ingestion.prometheus_scrape.enabled }}
{{- range $i, $target := .Values.ingestion.prometheus_scrape.targets }}
- prometheus_scrape_{{ $i }}
{{- end }}
{{- end }}
{{- if .Values.ingestion.kubernetes_events.enabled }}
- kubernetes_events
{{- end }}
{{- end -}}

{{/*
Resolve a pipeline input reference.
"_last_transform" → finalOutput (includes exactly_once_id if enabled)
"_sources" → logSourceNames
anything else → literal component name
*/}}
{{- define "pleme-vector.resolveInput" -}}
{{- $input := .input -}}
{{- $ctx := .ctx -}}
{{- if eq $input "_last_transform" -}}
  {{- include "pleme-vector.finalOutput" $ctx -}}
{{- else if eq $input "_sources" -}}
  {{- include "pleme-vector.logSourceNames" $ctx -}}
{{- else -}}
  {{- $input -}}
{{- end -}}
{{- end -}}

{{/*
Resolve a tap point to the Vector component name it reads from.
Returns empty string if the target transform is not enabled.
*/}}
{{- define "pleme-vector.tapPointInput" -}}
{{- $point := .point -}}
{{- $ctx := .ctx -}}
{{- if eq $point "pre_transform" -}}
  {{- include "pleme-vector.logSourceNames" $ctx -}}
{{- else if eq $point "post_k8s_enrich" -}}
  {{- if $ctx.Values.transform.kubernetes_metadata.enabled -}}k8s_enrich{{- end -}}
{{- else if eq $point "post_json_parse" -}}
  {{- if $ctx.Values.transform.json_parse.enabled -}}json_parse{{- end -}}
{{- else if eq $point "post_normalize" -}}
  {{- if $ctx.Values.transform.log_level_normalize.enabled -}}log_level_normalize{{- end -}}
{{- else if eq $point "post_event_detect" -}}
  {{- if $ctx.Values.transform.akeyless_event_detect.enabled -}}akeyless_event_detect{{- end -}}
{{- else if eq $point "post_experiment_tag" -}}
  {{- if $ctx.Values.transform.experiment_tag.enabled -}}experiment_tag{{- end -}}
{{- else if eq $point "post_product_detect" -}}
  {{- if $ctx.Values.transform.product_detect.enabled -}}product_detect{{- end -}}
{{- else if eq $point "post_transform" -}}
  {{- include "pleme-vector.lastLogTransform" $ctx -}}
{{- end -}}
{{- end -}}

{{/*
Generate a traffic operations sink from a destination config.
Args (dict): name, inputName, destType, dest, labels, ctx

Supports four destination types:
  loki    → Loki with labels (for LogQL querying via MCP)
  vector  → Vector gRPC (for chaining to downstream instances)
  file    → JSON lines (for offline analysis)
  console → stdout (for quick debug)
*/}}
{{- define "pleme-vector.trafficOpSink" -}}
{{- $name := .name -}}
{{- $inputName := .inputName -}}
{{- $destType := .destType -}}
{{- $dest := .dest -}}
{{- $labels := .labels -}}
{{- $ctx := .ctx -}}
{{- $tier := .deliveryTier | default "" -}}
{{- /* ★ Two failure modes this guard closes, both silent before.
       (1) NIL POINTER. Each branch reads `$dest.<destType>.…` without checking
       that the sub-map exists, so `destination: {type: loki}` with no `loki:`
       block -- the exact shape values.yaml documents -- died with
         nil pointer evaluating interface {}.endpoint
       from deep inside a helper, naming neither the traffic op nor the values
       key at fault.
       (2) SILENT DISAPPEARANCE. The if/else-if chain has no else, so ANY
       destType outside the four supported ones rendered NOTHING AT ALL: no
       error, no warning, `√ Loaded`, and the whole tap or traffic-op block
       simply absent. An operator asking for kafka got a clean-looking deploy
       that shipped their data nowhere. That is the worst class of defect in
       this chart, and it was invisible to `vector validate` by construction --
       there was nothing in the config to validate. */}}
{{- $known := list "loki" "vector" "file" "console" -}}
{{- if not (has $destType $known) -}}
{{- fail (printf "traffic-op/tap sink %q: destination.type %q is not supported (expected one of loki, vector, file, console). It used to render NOTHING silently, so the data went nowhere with no diagnostic." $name $destType) -}}
{{- end -}}
{{- if not (index $dest $destType) -}}
{{- fail (printf "traffic-op/tap sink %q: destination.type is %q but no `%s:` block is present under that destination, so its settings (endpoint/address/path) cannot be read." $name $destType $destType) -}}
{{- end -}}
{{- if eq $destType "loki" }}
      {{ $name }}:
        type: loki
        inputs:
          {{- if contains ", " $inputName }}
          {{- range splitList ", " $inputName }}
          - {{ . }}
          {{- end }}
          {{- else }}
          - {{ $inputName }}
          {{- end }}
        endpoint: {{ $dest.loki.endpoint | quote }}
        encoding:
          codec: json
        {{- if $dest.loki.batch_max_bytes }}
        batch:
          max_bytes: {{ int64 $dest.loki.batch_max_bytes }}
          timeout_secs: {{ $dest.loki.batch_timeout_secs | default 2 }}
        {{- end }}
        labels:
          {{- range $k, $v := $labels }}
          {{ $k }}: {{ $v | quote }}
          {{- end }}
          cluster: {{ $ctx.Values.cluster | quote }}
          environment: {{ $ctx.Values.environment | quote }}
        {{- if eq $tier "tier1" }}
        buffer:
          type: disk
          max_size: 2147483648
          when_full: block
        acknowledgements:
          enabled: true
        request:
          retry_max_duration_secs: 3600
        {{- else if eq $tier "tier2" }}
        buffer:
          type: disk
          max_size: 5368709120
          when_full: block
        acknowledgements:
          enabled: true
        request:
          retry_max_duration_secs: 3600
        {{- end }}
{{- else if eq $destType "vector" }}
      {{ $name }}:
        type: vector
        inputs:
          {{- if contains ", " $inputName }}
          {{- range splitList ", " $inputName }}
          - {{ . }}
          {{- end }}
          {{- else }}
          - {{ $inputName }}
          {{- end }}
        address: {{ $dest.vector.address | quote }}
        compression: true
{{- else if eq $destType "file" }}
      {{ $name }}:
        type: file
        inputs:
          {{- if contains ", " $inputName }}
          {{- range splitList ", " $inputName }}
          - {{ . }}
          {{- end }}
          {{- else }}
          - {{ $inputName }}
          {{- end }}
        path: {{ $dest.file.path | default (printf "/var/lib/vector/ops/%s/%%Y-%%m-%%d-%%H.jsonl" $name) | quote }}
        encoding:
          codec: json
{{- else if eq $destType "console" }}
      {{ $name }}:
        type: console
        inputs:
          {{- if contains ", " $inputName }}
          {{- range splitList ", " $inputName }}
          - {{ . }}
          {{- end }}
          {{- else }}
          - {{ $inputName }}
          {{- end }}
        encoding:
          codec: json
        target: {{ $dest.console.target | default "stdout" }}
{{- end }}
{{- end -}}

{{/*
═══════════════════════════════════════════════════════════════════
DELIVERY GUARANTEE HELPERS
═══════════════════════════════════════════════════════════════════
*/}}

{{/*
Returns "true" if this instance is a guaranteed-mode producer.
*/}}
{{- define "pleme-vector.isProducer" -}}
{{- if and (eq .Values.delivery.guarantee "guaranteed") (eq .Values.delivery.role "producer") -}}true{{- end -}}
{{- end -}}

{{/*
Returns "true" if this instance is a guaranteed-mode consumer.
*/}}
{{- define "pleme-vector.isConsumer" -}}
{{- if and (eq .Values.delivery.guarantee "guaranteed") (eq .Values.delivery.role "consumer") -}}true{{- end -}}
{{- end -}}

{{/*
Emit the buffer configuration block for a sink based on delivery guarantee level.
*/}}
{{- define "pleme-vector.deliveryBufferConfig" -}}
{{- if .Values.breathing.enabled }}
        buffer:
          type: disk
          max_size: {{ int64 .Values.breathing.vector.buffer_size }}
          when_full: {{ .Values.breathing.vector.when_full }}
{{- else if eq .Values.delivery.guarantee "durable" }}
        buffer:
          type: disk
          max_size: 5368709120
          when_full: block
{{- else if and (eq .Values.delivery.guarantee "guaranteed") (eq .Values.delivery.role "consumer") }}
        buffer:
          type: disk
          max_size: 2147483648
          when_full: block
{{- else if eq .Values.delivery.buffer.type "disk" }}
        buffer:
          type: disk
          max_size: {{ int64 .Values.delivery.buffer.max_size }}
          when_full: {{ .Values.delivery.buffer.when_full }}
{{- else }}
        buffer:
          type: memory
          max_events: {{ int64 (.Values.delivery.buffer.max_events | default 500) }}
          when_full: {{ .Values.delivery.buffer.when_full | default "drop_newest" }}
{{- end }}
{{- end -}}

{{/*
Emit the retry/request configuration block based on delivery guarantee level.
*/}}
{{- define "pleme-vector.deliveryRetryConfig" -}}
{{- if or (eq .Values.delivery.guarantee "durable") (eq .Values.delivery.role "consumer") }}
        request:
          retry_max_duration_secs: 3600
          retry_initial_backoff_secs: {{ .Values.delivery.retry.initial_backoff_secs }}
          retry_max_backoff_secs: {{ .Values.delivery.retry.max_backoff_secs }}
{{- else }}
        request:
          retry_max_duration_secs: {{ .Values.delivery.retry.max_duration_secs }}
{{- end }}
{{- end -}}

{{/*
Emit the acknowledgements configuration block based on delivery guarantee level.
*/}}
{{/*
Returns "true" when at least one enabled source can honour sink
acknowledgements. Vector warns -- "Source has acknowledgements enabled by a
sink, but acknowledgements are not supported by this source. Silent data loss
could occur." -- when a sink turns acks on over a source whose
can_acknowledge() is false. In the pinned 0.41.1 that is kubernetes_logs
(src/sources/kubernetes_logs/mod.rs:553), exec, internal_metrics, statsd and
http_client; journald, http_server, splunk_hec, opentelemetry, nats and vector
all return true.
*/}}
{{- define "pleme-vector.hasAckCapableSource" -}}
{{- if or .Values.ingestion.journald.enabled .Values.ingestion.http_server.enabled .Values.ingestion.splunk_hec.enabled .Values.ingestion.burst_forge_http.enabled .Values.ingestion_opentelemetry.enabled .Values.processing.vector_source.enabled -}}true{{- end -}}
{{- end -}}

{{- define "pleme-vector.deliveryAckConfig" -}}
{{- /* The consumer path keeps its unconditional ack: its source is `nats`,
       which CAN acknowledge. Only the durable/opt-in standalone path is
       gated -- it was emitting `acknowledgements: enabled: true` for any
       `guarantee: durable` regardless of whether a single enabled source
       could honour it, which is a promise the components cannot keep.
       "durable" in this chart genuinely means disk buffer + when_full: block
       + infinite retry; all three are real and all three still render. Only
       the ack line was the overstatement. */ -}}
{{- if eq .Values.delivery.role "consumer" }}
        acknowledgements:
          enabled: true
{{- else if and (or (eq .Values.delivery.guarantee "durable") .Values.delivery.acknowledgements) (eq (include "pleme-vector.hasAckCapableSource" .) "true") }}
        acknowledgements:
          enabled: true
{{- end }}
{{- end -}}
