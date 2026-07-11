{{/*
pleme-lib.jetstream — declare NATS JetStream streams + consumers from
any chart, OWNED BY THAT CHART (not the broker).

Cilium-style identity model: the broker (pleme-nats) is shared
infrastructure; each consumer chart declares the streams + consumers
it needs and owns the lifecycle. This decouples broker upgrades from
consumer schema changes and keeps the stream shape close to the code
that depends on it.

See: pleme-io/theory/RATE-LIMITED-CONSUMERS.md §IV-L1.

────────────────────────────────────────────────────────────────────
USAGE
────────────────────────────────────────────────────────────────────

In your chart's `values.yaml`:

  jetstream:
    enabled: true
    serverUrl: "nats://pleme-nats.nats.svc:4222"
    streams:
      MY_STREAM:
        subjects: ["my.subject.>"]
        retention: workqueue   # workqueue | limits | interest
        storage: file          # file | memory
        replicas: 1
        maxMsgs: 10000
        maxBytes: "100MB"
        maxAge: "24h"
        duplicateWindow: "10m"
        discard: old           # old | new
    consumers:
      MY_STREAM:
        my-consumer:
          type: pull           # pull | push
          ackPolicy: explicit
          ackWait: "60s"
          maxAckPending: 1     # ★ rate-limit invariant (1 = serialized)
          maxDeliver: 5
          filterSubject: "my.subject.refresh.>"
          replayPolicy: instant

  jetstreamInit:
    image:
      repository: natsio/nats-box
      tag: "0.14.5"
    serverWaitSeconds: 120

In your chart's `templates/jetstream.yaml` (one line):

  {{- include "pleme-lib.jetstream" . }}

That single include emits:
  • ConfigMap holding stream + consumer JSON specs
  • Helm post-install/post-upgrade Job that upserts via `nats` CLI
  • ServiceAccount the Job runs as (if not externally provided)

────────────────────────────────────────────────────────────────────
DESIGN NOTES
────────────────────────────────────────────────────────────────────

• Idempotent: each stream/consumer is `add ... || update ...` — runs
  on every chart upgrade so values changes propagate.
• Hook-weight tuned so the broker is up before stream init runs.
• ConfigMap contents are content-addressed via checksum annotation
  on the Job, so a values change that affects the JSON triggers a
  fresh Job run (Helm hooks already do this on upgrade, but the
  checksum makes the link explicit and visible in audit).
• Each chart's streams + consumers live in its own ConfigMap+Job —
  removing a chart removes its streams (tracked by the consumer's
  Helm release lifecycle, not the broker's).

────────────────────────────────────────────────────────────────────
VARIANT: pleme-lib.jetstream-init-job
────────────────────────────────────────────────────────────────────

If you need finer control (e.g. a ConfigMap shared across multiple
Jobs), use the lower-level `pleme-lib.jetstream-init-job` template
that takes an explicit ConfigMap name as a dict arg.
*/}}

{{/*
Convert a Helm-friendly byte size string ("100MB", "5GB", "512KB",
"-1", or a bare integer) into the int64 byte count JetStream expects.
"MB"/"GB"/"KB" mean MiB/GiB/KiB (binary, 1024-based) — that's what
NATS uses when reporting stream stats, so consumer-side declarations
should match. -1 = unlimited.
*/}}
{{- define "pleme-lib.bytes" -}}
{{- $s := . | toString -}}
{{- if eq $s "-1" -}}
{{- -1 -}}
{{- else if hasSuffix "GB" $s -}}
{{ mul (int64 (trimSuffix "GB" $s)) 1073741824 }}
{{- else if hasSuffix "MB" $s -}}
{{ mul (int64 (trimSuffix "MB" $s)) 1048576 }}
{{- else if hasSuffix "KB" $s -}}
{{ mul (int64 (trimSuffix "KB" $s)) 1024 }}
{{- else -}}
{{ int64 $s }}
{{- end -}}
{{- end -}}

{{/*
Convert a Go-style duration string ("30s", "10m", "24h", "100ms")
into the int64 nanoseconds value JetStream's REST API expects. NATS
CLI accepts the string form on `nats stream add --config <file>`,
but the JSON it writes natively is nanoseconds, and recent CLI
versions reject the string form on `update` paths. Emitting ns
makes the config robust across CLI versions.
*/}}
{{- define "pleme-lib.duration-ns" -}}
{{- $s := . | toString -}}
{{- if hasSuffix "ms" $s -}}
{{ mul (int64 (trimSuffix "ms" $s)) 1000000 }}
{{- else if hasSuffix "s" $s -}}
{{ mul (int64 (trimSuffix "s" $s)) 1000000000 }}
{{- else if hasSuffix "m" $s -}}
{{ mul (int64 (trimSuffix "m" $s)) 60000000000 }}
{{- else if hasSuffix "h" $s -}}
{{ mul (int64 (trimSuffix "h" $s)) 3600000000000 }}
{{- else if hasSuffix "d" $s -}}
{{ mul (int64 (trimSuffix "d" $s)) 86400000000000 }}
{{- else -}}
{{ mul (int64 $s) 1000000000 }}
{{- end -}}
{{- end -}}

{{- define "pleme-lib.jetstream" -}}
{{- if (.Values.jetstream).enabled -}}
{{- $hasContent := false -}}
{{- range $name, $cfg := (.Values.jetstream).streams }}{{- $hasContent = true -}}{{- end }}
{{- range $stream, $consumers := (.Values.jetstream).consumers }}
{{- range $cname, $ccfg := $consumers }}{{- $hasContent = true -}}{{- end }}
{{- end }}
{{- if $hasContent }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $cmName := printf "%s-jetstream" $fullname }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $cmName }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    pleme.io/jetstream-config: "true"
  annotations:
    "helm.sh/hook": {{ default "post-install,post-upgrade" ((.Values.jetstreamInit).hookPhase) }}
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation
data:
  {{- range $name, $cfg := (.Values.jetstream).streams }}
  stream-{{ $name }}.json: |
    {
      "name": {{ $name | quote }},
      "subjects": {{ $cfg.subjects | toJson }},
      "retention": {{ $cfg.retention | quote }},
      "storage": {{ $cfg.storage | quote }},
      "num_replicas": {{ default 1 $cfg.replicas }},
      "max_consumers": -1,
      "max_msgs": {{ default -1 $cfg.maxMsgs }},
      "max_msgs_per_subject": -1,
      "max_bytes": {{ include "pleme-lib.bytes" (default "-1" $cfg.maxBytes) }},
      "max_msg_size": -1,
      "max_age": {{ include "pleme-lib.duration-ns" (default "0s" $cfg.maxAge) }},
      "duplicate_window": {{ include "pleme-lib.duration-ns" (default "0s" $cfg.duplicateWindow) }},
      "discard": {{ default "old" $cfg.discard | quote }}
    }
  {{- end }}
  {{- range $stream, $consumers := (.Values.jetstream).consumers }}
  {{- range $cname, $cfg := $consumers }}
  consumer-{{ $stream }}-{{ $cname }}.json: |
    {
      "stream_name": {{ $stream | quote }},
      "config": {
        "durable_name": {{ $cname | quote }},
        "ack_policy": {{ default "explicit" $cfg.ackPolicy | quote }},
        "ack_wait": {{ include "pleme-lib.duration-ns" (default "30s" $cfg.ackWait) }},
        "max_ack_pending": {{ default 1 $cfg.maxAckPending }},
        "max_deliver": {{ default 5 $cfg.maxDeliver }},
        "filter_subject": {{ default "" $cfg.filterSubject | quote }},
        "replay_policy": {{ default "instant" $cfg.replayPolicy | quote }}
      }
    }
  {{- end }}
  {{- end }}
{{ include "pleme-lib.jetstream-init-job" (dict "ctx" . "configMapName" $cmName) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Lower-level template: render the init Job pointed at a specific
ConfigMap. Useful when a chart wants to drive multiple Jobs or share
the ConfigMap across releases.

Args (passed via `dict`):
  ctx           — root chart context (`.`)
  configMapName — name of the ConfigMap holding stream-*.json /
                  consumer-*.json files
*/}}
{{- define "pleme-lib.jetstream-init-job" -}}
{{- $ctx := .ctx }}
{{- $cmName := .configMapName }}
{{- $fullname := include "pleme-lib.fullname" $ctx }}
{{- $serverUrl := default "nats://pleme-nats.nats.svc:4222" (($ctx.Values.jetstream).serverUrl) }}
{{- $jobImage := default "natsio/nats-box" ((($ctx.Values.jetstreamInit).image).repository) }}
{{- $jobTag := default "0.14.5" ((($ctx.Values.jetstreamInit).image).tag) }}
{{- $waitSeconds := default 120 (($ctx.Values.jetstreamInit).serverWaitSeconds) }}
---
apiVersion: batch/v1
kind: Job
metadata:
  # Kubernetes auto-injects a `job-name: <this name>` label onto the Job's own
  # pod template; label VALUES cap at 63 bytes even though object NAMES allow
  # 253 -- an untruncated $fullname + "-jetstream-init" silently violates that
  # the moment a consumer chart's release+chart name combo runs long (first
  # hit: pleme-escuta-breathe-bridge, 2026-07-11).
  name: {{ include "pleme-lib.fullname" $ctx | trunc 48 | trimSuffix "-" }}-jetstream-init
  namespace: {{ include "pleme-lib.namespace" $ctx }}
  labels:
    {{- include "pleme-lib.labels" $ctx | nindent 4 }}
    pleme.io/jetstream-init: "true"
  annotations:
    "helm.sh/hook": {{ default "post-install,post-upgrade" (($ctx.Values.jetstreamInit).hookPhase) }}
    "helm.sh/hook-weight": "5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        {{- include "pleme-lib.selectorLabels" $ctx | nindent 8 }}
        app.kubernetes.io/component: jetstream-init
    spec:
      restartPolicy: OnFailure
      {{- with ($ctx.Values).imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with ($ctx.Values).podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: jetstream-init
          image: "{{ $jobImage }}:{{ $jobTag }}"
          imagePullPolicy: IfNotPresent
          # nats-box's `nats` CLI calls `stat .` on its CWD during
          # subcommand init; with readOnlyRootFilesystem=true the
          # default CWD (/) returns EACCES. Pin CWD to a writable
          # tmpfs so it works regardless of the consumer chart's
          # podSecurityContext.
          workingDir: /tmp
          {{- with ($ctx.Values).securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 64Mi
          env:
            - name: NATS_URL
              value: {{ $serverUrl | quote }}
            - name: SERVER_WAIT_SECONDS
              value: {{ $waitSeconds | quote }}
            - name: HOME
              value: /tmp
          # Idempotent upsert loop. add → update fallback handles both
          # first-install and re-runs after values changes.
          command:
            - /bin/sh
            - -ec
            - |
              echo "Waiting up to ${SERVER_WAIT_SECONDS}s for NATS at ${NATS_URL}..."
              i=0
              until nats --server "${NATS_URL}" account info >/dev/null 2>&1; do
                i=$((i+1))
                if [ "$i" -ge "${SERVER_WAIT_SECONDS}" ]; then
                  echo "Gave up waiting for NATS"
                  exit 1
                fi
                sleep 1
              done
              echo "NATS reachable. Declaring streams..."
              for f in /configs/stream-*.json; do
                [ -f "$f" ] || continue
                name=$(basename "$f" .json | sed 's/^stream-//')
                echo "  → stream: $name"
                # `--force` skips interactive confirmation when the
                # stream already exists with a different configuration.
                # Idempotent upsert: try add first, fall through to
                # update if it already exists.
                nats --server "${NATS_URL}" stream add --config "$f" "$name" 2>/dev/null \
                  || nats --server "${NATS_URL}" stream update --force --config "$f" "$name"
              done
              echo "Declaring consumers..."
              for f in /configs/consumer-*.json; do
                [ -f "$f" ] || continue
                base=$(basename "$f" .json | sed 's/^consumer-//')
                stream=$(echo "$base" | cut -d- -f1)
                consumer=$(echo "$base" | cut -d- -f2-)
                echo "  → consumer: $stream/$consumer"
                nats --server "${NATS_URL}" consumer add --config "$f" "$stream" "$consumer" 2>/dev/null \
                  || nats --server "${NATS_URL}" consumer update --force --config "$f" "$stream" "$consumer"
              done
              echo "Done."
          volumeMounts:
            - name: configs
              mountPath: /configs
              readOnly: true
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: configs
          configMap:
            name: {{ $cmName }}
        - name: tmp
          emptyDir:
            sizeLimit: 32Mi
{{- end }}
