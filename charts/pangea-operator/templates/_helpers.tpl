{{/*
pangea-operator helpers — delegates to pleme-lib
*/}}

{{- define "pangea-operator.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pangea-operator.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
