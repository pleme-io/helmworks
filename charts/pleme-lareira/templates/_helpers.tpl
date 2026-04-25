{{/*
pleme-lareira: helpers.

We don't redefine name / fullname / labels / namespace — those come from
pleme-lib unchanged (because library-template helpers operate in the
consumer's chart context, .Chart.Name resolves to the consumer's name).

Helpers here are pleme-lareira-specific glue.
*/}}

{{/*
pleme-lareira.serviceAnnotations — combine cloudflared.serviceAnnotations
with any user-provided service annotations. Use in consumer
templates/service.yaml:

  metadata:
    annotations:
      {{- include "pleme-lareira.serviceAnnotations" . | nindent 4 }}
*/}}
{{- define "pleme-lareira.serviceAnnotations" -}}
{{- include "pleme-lareira.cloudflared.serviceAnnotations" . }}
{{- with (.Values.service).annotations }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
pleme-lareira.requireWhenEnabled — fail-fast helper for required values
on top-level enabled=true. Usage:

  {{- include "pleme-lareira.requireWhenEnabled" (dict "ctx" . "key" "image.repository") }}

(unused right now but reserved for consumer charts.)
*/}}
{{- define "pleme-lareira.requireWhenEnabled" -}}
{{- $ctx := .ctx -}}
{{- if $ctx.Values.enabled -}}
{{- $val := index $ctx.Values (splitList "." .key | first) -}}
{{- /* TODO: full nested traversal; today only top-level keys are supported */ -}}
{{- if not $val -}}
{{- fail (printf "pleme-lareira: %s is required when .Values.enabled = true" .key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
