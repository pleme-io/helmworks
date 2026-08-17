{{/*
_bus.tpl — typed message-bus selection for viper-configured Go microservices.

OFF BY DEFAULT. Every helper here returns the empty string unless
`.Values.bus.enabled` is set, and `templates/deployment.yaml` keeps its
original, untouched code path in that case. A chart rendered without a
`bus:` block is byte-identical to the same chart before this file existed.

WHY THIS EXISTS
---------------
The target application picks its message-queue implementation from viper
config, NOT from a code fork. Two INDEPENDENT keys select it, so one queue
family can move to NATS while every other family stays on RabbitMQ:

  mq_type      — the general queue family
  bis_mq_type  — the second (billing/statistics) queue family

Both are registered as viper defaults and both default to RABBITMQ.

THE ENV VAR NAMES ARE PREFIXED — this is the load-bearing detail
-----------------------------------------------------------------
Each service builds its own viper instance and calls SetEnvPrefix with its
own name, then calls AutomaticEnv() on it. viper's mergeWithEnvPrefix
therefore resolves `mq_type` to `<PREFIX>_MQ_TYPE`, uppercased. With no
SetEnvKeyReplacer configured, underscores are preserved verbatim.

An UNPREFIXED `MQ_TYPE` is read by NOTHING. Setting it is a silent no-op.

NOT EVERY SERVICE READS mq_type
-------------------------------
Only the services that actually construct an MQConfigManager have a bus to
select; giving one to any other service emits a knob that does nothing. The
chart cannot know another codebase's roster, so it is supplied as
`bus.knownServices` (a values list). Empty ⇒ the guard is inactive.

VALUES ARE CASE-SENSITIVE ON THE WIRE
-------------------------------------
GetMQ() dispatches with a Go `switch` on the raw string, so the value must
match the Go constant EXACTLY. The constants are uppercase: "NATS",
"RABBITMQ", "AWS".

A lowercase `nats` falls through to `default:` and the service dies with
"unknown message queue type". This chart therefore takes readable lowercase
names and maps them to the wire constant, failing the RENDER on anything
unrecognised rather than shipping a pod that crashes on boot.
*/}}

{{/*
The set of services that actually read mq_type, supplied by the caller as
`bus.knownServices`. Selecting a bus for anything outside a NON-EMPTY set
produces a knob that does nothing, so it is a render error unless the caller
explicitly acknowledges the risk with `bus.allowUnknownService: true`. An
empty/absent list leaves the guard inactive.
*/}}
{{- define "pleme-microservice.bus.knownServices" -}}
{{- join " " ((.Values.bus | default dict).knownServices | default list) -}}
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
{{- $knownRaw := include "pleme-microservice.bus.knownServices" . -}}
{{- if and (not $bus.allowUnknownService) (ne $knownRaw "") -}}
{{- $known := splitList " " $knownRaw -}}
{{- if not (has $service $known) -}}
{{- fail (printf "bus: service %q is not in bus.knownServices (%s), so it does not construct an MQConfigManager — the env var would be silently ignored; set bus.allowUnknownService=true to override" $service (join ", " $known)) -}}
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
