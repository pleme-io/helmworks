{{/*
kenshi helpers — delegates to pleme-lib
*/}}

{{- define "kenshi.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "kenshi.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
