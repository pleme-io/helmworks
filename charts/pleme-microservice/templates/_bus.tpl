{{/*
_bus.tpl — typed message-bus selection for akeyless-main-repo microservices.

OFF BY DEFAULT. Every helper here returns the empty string unless
`.Values.bus.enabled` is set, and `templates/deployment.yaml` keeps its
original, untouched code path in that case. A chart rendered without a
`bus:` block is byte-identical to the same chart before this file existed.

WHY THIS EXISTS
---------------
akeyless-main-repo picks its message-queue implementation from viper config,
NOT from a code fork. Two INDEPENDENT keys select it, so one queue family can
move to NATS while every other family stays on RabbitMQ:

  mq_type      — the general queue family
  bis_mq_type  — the BIS (billing/statistics) queue family

Both are registered in go/src/microservices/common/mqueue/config.go
(setGeneralDefaults) and both default to RABBITMQ.

THE ENV VAR NAMES ARE PREFIXED — this is the load-bearing detail
-----------------------------------------------------------------
Each service builds its own viper instance and calls SetEnvPrefix with its
own name, then infra/config.NewFileConfigManager calls AutomaticEnv() on it.
viper's mergeWithEnvPrefix therefore resolves `mq_type` to
`<PREFIX>_MQ_TYPE`, uppercased. There is NO SetEnvKeyReplacer anywhere in
go/src, so underscores are preserved verbatim.

An UNPREFIXED `MQ_TYPE` is read by NOTHING. Setting it is a silent no-op.

Only these five services construct an MQConfigManager, so only these five
have a bus to select. kfm, sdr and the gateway have no mqueue usage at all
and must never be given a bus block:

  service  viper prefix   general knob        BIS knob
  -------  ------------   -----------------   ---------------------
  auth     auth           AUTH_MQ_TYPE        AUTH_BIS_MQ_TYPE
  bis      bis            BIS_MQ_TYPE         BIS_BIS_MQ_TYPE
  gator    gator          GATOR_MQ_TYPE       GATOR_BIS_MQ_TYPE
  logan    logan          LOGAN_MQ_TYPE       LOGAN_BIS_MQ_TYPE
  uam      uam            UAM_MQ_TYPE         UAM_BIS_MQ_TYPE

VALUES ARE CASE-SENSITIVE ON THE WIRE
-------------------------------------
GetMQ() dispatches with a Go `switch` on the raw string, so the value must
match the Go constant EXACTLY. The constants are uppercase:

  busnats.MQType   = "NATS"      go/src/infra/mqueue/bus/busnats/adapter.go:17
  rabbitmq.MQType  = "RABBITMQ"  go/src/infra/mqueue/rabbitmq/message_queue.go:27
  aws_sqs.MQType   = "AWS"       go/src/infra/mqueue/aws-sqs/message_queue.go:26

A lowercase `nats` falls through to `default:` and the service dies with
"unknown message queue type". This chart therefore takes readable lowercase
names and maps them to the wire constant, failing the RENDER on anything
unrecognised rather than shipping a pod that crashes on boot.
*/}}

{{/*
The verified set of services that actually read mq_type. Selecting a bus for
anything outside this set produces a knob that does nothing, so it is a
render error unless the caller explicitly acknowledges the risk with
`bus.allowUnknownService: true`.
*/}}
{{- define "pleme-microservice.bus.knownServices" -}}
auth bis gator logan uam
{{- end }}

{{/*
Map a readable values-level queue name to the exact Go constant. Anything
outside the map is a render-time failure, never a runtime surprise.
*/}}
{{- define "pleme-microservice.bus.wire" -}}
{{- $wire := dict "rabbitmq" "RABBITMQ" "nats" "NATS" "aws" "AWS" -}}
{{- if not (hasKey $wire (toString .)) -}}
{{- fail (printf "bus: unknown queue type %q — must be one of rabbitmq, nats, aws" (toString .)) -}}
{{- end -}}
{{- index $wire (toString .) -}}
{{- end }}

{{/*
Render the bus env vars as a YAML array, or nothing at all when the block is
absent or disabled. Consumed by templates/deployment.yaml.
*/}}
{{- define "pleme-microservice.bus.env" -}}
{{- $bus := .Values.bus | default dict -}}
{{- if $bus.enabled -}}
{{- $service := required "bus.service is required when bus.enabled is true" $bus.service | toString -}}
{{- if not $bus.allowUnknownService -}}
{{- $known := splitList " " (include "pleme-microservice.bus.knownServices" .) -}}
{{- if not (has $service $known) -}}
{{- fail (printf "bus: service %q does not read mq_type (only %s construct an MQConfigManager) — the env var would be silently ignored; set bus.allowUnknownService=true to override" $service (join ", " $known)) -}}
{{- end -}}
{{- end -}}
{{- $prefix := upper $service -}}
{{- $families := $bus.families | default dict -}}
{{- if not (or (hasKey $families "general") (hasKey $families "bis")) -}}
{{- fail "bus: bus.enabled is true but neither families.general nor families.bis is set — the block would emit no selection at all" -}}
{{- end -}}
{{- $selected := list -}}
{{- with $families.general -}}{{- $selected = append $selected (include "pleme-microservice.bus.wire" .) -}}{{- end -}}
{{- with $families.bis -}}{{- $selected = append $selected (include "pleme-microservice.bus.wire" .) -}}{{- end -}}
{{- if and (has "NATS" $selected) (not (or $bus.natsUrl $bus.natsUrlInternal)) -}}
{{- fail "bus: a queue family selects nats but neither bus.natsUrl nor bus.natsUrlInternal is set — GetMQ() would fail at boot with 'nats_url is not configured'" -}}
{{- end -}}
{{- with $families.general }}
- name: {{ printf "%s_MQ_TYPE" $prefix }}
  value: {{ include "pleme-microservice.bus.wire" . | quote }}
{{- end }}
{{- with $families.bis }}
- name: {{ printf "%s_BIS_MQ_TYPE" $prefix }}
  value: {{ include "pleme-microservice.bus.wire" . | quote }}
{{- end }}
{{- with $bus.natsUrl }}
- name: {{ printf "%s_NATS_URL" $prefix }}
  value: {{ . | quote }}
{{- end }}
{{- with $bus.natsUrlInternal }}
- name: {{ printf "%s_NATS_URL_INTERNAL" $prefix }}
  value: {{ . | quote }}
{{- end }}
{{- end -}}
{{- end }}
