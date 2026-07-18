{{/*
porto-specific helpers. Generic naming/labels live in pleme-lib.
*/}}

{{/* Render porto's config.yaml from values.porto.* (the typed serde
     RegistryConfig the server parses; deny_unknown_fields — an unknown key is a
     parse-time rejection). `maxBodyBytes` maps to the `max_body_bytes: Option`
     field: an empty value omits it (None → no body ceiling, layers stream). */}}
{{- define "pleme-porto.config" -}}
listen: {{ .Values.porto.listen | quote }}
{{- if .Values.porto.maxBodyBytes }}
max_body_bytes: {{ .Values.porto.maxBodyBytes }}
{{- end }}
{{- end -}}
