{{- define "pleme-sui.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-sui.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-sui.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "pleme-sui.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}

{{- define "pleme-sui.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pleme-sui.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
