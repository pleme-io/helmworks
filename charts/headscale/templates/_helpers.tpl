{{/*
headscale helpers — delegates to pleme-lib
*/}}

{{- define "headscale.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "headscale.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
