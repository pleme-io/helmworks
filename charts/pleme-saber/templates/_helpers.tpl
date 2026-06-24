{{/*
pleme-saber helpers — delegates to pleme-lib
*/}}

{{- define "pleme-saber.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-saber.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
