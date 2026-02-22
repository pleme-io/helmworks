{{/*
pleme-cache helpers — delegates to pleme-lib
*/}}

{{- define "pleme-cache.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-cache.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
