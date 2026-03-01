{{/*
Sekiban chart helpers — delegates to pleme-lib
*/}}

{{- define "sekiban.webhookName" -}}
{{ include "pleme-lib.fullname" . }}-integrity-gate
{{- end }}

{{- define "sekiban.certName" -}}
{{ include "pleme-lib.fullname" . }}-webhook-cert
{{- end }}

{{- define "sekiban.webhookServiceName" -}}
{{ include "pleme-lib.fullname" . }}
{{- end }}
