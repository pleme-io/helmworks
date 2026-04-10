{{/*
pleme-attic helpers — delegates to pleme-lib
*/}}

{{- define "pleme-attic.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-attic.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-attic.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "pleme-attic.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}

{{- define "pleme-attic.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pleme-attic.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "pleme-attic.postgresFullname" -}}
{{- printf "postgres-%s" (include "pleme-attic.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
