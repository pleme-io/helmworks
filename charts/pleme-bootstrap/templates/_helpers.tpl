{{/*
pleme-bootstrap helpers — delegates to pleme-lib
*/}}

{{- define "pleme-bootstrap.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-bootstrap.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
