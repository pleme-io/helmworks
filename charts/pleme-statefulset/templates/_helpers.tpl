{{/*
pleme-statefulset helpers — delegates to pleme-lib
*/}}

{{- define "pleme-statefulset.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-statefulset.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
