{{/*
pleme-microservice helpers — delegates to pleme-lib
*/}}

{{- define "pleme-microservice.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-microservice.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
