{{/*
pleme-cronjob helpers — delegates to pleme-lib
*/}}

{{- define "pleme-cronjob.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-cronjob.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
