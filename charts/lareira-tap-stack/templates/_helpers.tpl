{{/*
lareira-tap-stack — composition helpers.

This is a THIN UMBRELLA: every workload is rendered by a subchart
(lareira-respiro / lareira-pangea-dashboards). These helpers exist only to
(a) name the chart consistently and (b) DERIVE the canonical JetStream stream
identity from the tap-cell name for the NOTES surface. There is NO bespoke
resource template in M0.
*/}}

{{- define "lareira-tap-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "lareira-tap-stack.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "lareira-tap-stack.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: lareira
{{- end -}}

{{/*
lareira-tap-stack.streamName — derive a NATS-token-safe JetStream stream name
from the tap-cell `tap.name`. TYPED EMISSION: built from Helm string-pipeline
primitives (upper | replace | trimSuffix), never a printf of config syntax.
Falls back to the chart fullname when tap.name is unset (the default-off path).
NATS stream names cannot contain `.`/` `/`*`/`>` — we map `-` and `.` to `_`.
*/}}
{{- define "lareira-tap-stack.streamName" -}}
{{- $tap := .Values.tap -}}
{{- if $tap.name -}}
{{- $tap.name | upper | replace "-" "_" | replace "." "_" | trunc 63 | trimSuffix "_" -}}
{{- else -}}
{{- include "lareira-tap-stack.fullname" . | upper | replace "-" "_" | trunc 63 | trimSuffix "_" -}}
{{- end -}}
{{- end -}}
