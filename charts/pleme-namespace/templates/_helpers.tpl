{{/*
pleme-namespace helpers — delegates to pleme-lib
*/}}

{{- define "pleme-namespace.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-namespace.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
