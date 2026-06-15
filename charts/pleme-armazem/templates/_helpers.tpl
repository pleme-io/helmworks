{{/*
armázem-specific helpers. Generic naming/labels live in pleme-lib.
*/}}

{{/* Render the armázem config.yaml from values.armazem.* (the typed serde
     config the gateway parses; the backend is a typed sum, one arm active). */}}
{{- define "pleme-armazem.config" -}}
listen: {{ .Values.armazem.listen | quote }}
health_listen: {{ .Values.armazem.healthListen | quote }}
backend:
{{- if eq .Values.armazem.backend.type "fs" }}
  type: fs
  root: {{ .Values.armazem.backend.root | quote }}
{{- else }}
  {{- fail (printf "pleme-armazem: unsupported backend.type %q (M0 supports: fs)" .Values.armazem.backend.type) }}
{{- end }}
{{- end -}}
