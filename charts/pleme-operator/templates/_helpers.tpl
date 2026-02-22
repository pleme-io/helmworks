{{/*
pleme-operator helpers — delegates to pleme-lib
*/}}

{{- define "pleme-operator.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-operator.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
