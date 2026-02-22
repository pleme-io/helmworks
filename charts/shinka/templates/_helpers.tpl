{{/*
shinka helpers — delegates to pleme-lib
*/}}

{{- define "shinka.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "shinka.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
