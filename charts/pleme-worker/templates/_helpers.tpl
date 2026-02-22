{{/*
pleme-worker helpers — delegates to pleme-lib
*/}}

{{- define "pleme-worker.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-worker.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
