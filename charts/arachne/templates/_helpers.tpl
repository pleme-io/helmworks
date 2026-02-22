{{/*
arachne helpers — delegates to pleme-lib
*/}}

{{- define "arachne.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "arachne.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
