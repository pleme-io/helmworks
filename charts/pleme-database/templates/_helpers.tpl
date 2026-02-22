{{/*
pleme-database helpers — delegates to pleme-lib
*/}}

{{- define "pleme-database.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-database.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
