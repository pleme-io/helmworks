{{/*
iac-forge helpers — delegates to pleme-lib
*/}}

{{- define "iac-forge.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "iac-forge.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
