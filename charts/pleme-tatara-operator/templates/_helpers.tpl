{{- define "pleme-tatara-operator.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-tatara-operator.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-tatara-operator.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "pleme-tatara-operator.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}

{{- define "pleme-tatara-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pleme-tatara-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
