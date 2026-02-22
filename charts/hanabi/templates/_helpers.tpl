{{/*
hanabi helpers — delegates to pleme-lib
*/}}

{{- define "hanabi.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "hanabi.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
