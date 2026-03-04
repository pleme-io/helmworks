{{/*
pleme-gpu-workload helpers — delegates to pleme-lib
*/}}

{{- define "pleme-gpu-workload.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-gpu-workload.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
