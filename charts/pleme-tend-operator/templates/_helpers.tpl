{{- define "pleme-tend-operator.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-tend-operator.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-tend-operator.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "pleme-tend-operator.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}

{{- define "pleme-tend-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pleme-tend-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
