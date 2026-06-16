{{/*
gaveta helpers — delegates to pleme-lib
*/}}

{{- define "gaveta.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "gaveta.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
