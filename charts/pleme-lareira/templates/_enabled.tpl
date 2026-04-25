{{/*
pleme-lareira.enabled — master toggle helper.

Returns the string "true" when the consumer chart is opted-in, otherwise
the empty string. Use as a guard at the TOP of every consumer chart
template:

  {{- if include "pleme-lareira.enabled" . }}
  apiVersion: ...
  ...
  {{- end }}

Library charts can't gate the consumer's own .yaml files for them, so the
convention is enforced at the consumer level — but this helper centralises
the check so we can later add cluster-aware logic ("enabled only on rio")
without touching every chart.

The companion `pleme-lareira.fail-if-disabled` macro renders nothing on
disabled and a clear comment on enabled — useful for sanity-checking
helm template output.
*/}}
{{- define "pleme-lareira.enabled" -}}
{{- if .Values.enabled -}}
true
{{- end -}}
{{- end -}}

{{- define "pleme-lareira.disabled-comment" -}}
{{- if not .Values.enabled -}}
# pleme-lareira: chart disabled (.Values.enabled = false). Set enabled=true
# in your HelmRelease values to render this workload.
{{- end -}}
{{- end -}}
