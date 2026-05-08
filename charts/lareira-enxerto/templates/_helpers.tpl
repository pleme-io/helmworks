{{/*
lareira-enxerto — names + labels delegated to pleme-lib.
*/}}

{{- define "lareira-enxerto.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "lareira-enxerto.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "lareira-enxerto.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "lareira-enxerto.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}
