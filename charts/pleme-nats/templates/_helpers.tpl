{{/*
pleme-nats helpers — delegates name/labels to pleme-lib.
*/}}

{{- define "pleme-nats.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-nats.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-nats.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "pleme-nats.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}

{{- define "pleme-nats.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pleme-nats.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
URL the in-cluster client uses to reach this NATS deployment.
Used by tend-throttle / shinryu / vector via Helm value cross-refs.
*/}}
{{- define "pleme-nats.clientUrl" -}}
nats://{{ include "pleme-nats.fullname" . }}.{{ .Release.Namespace }}.svc:{{ .Values.service.ports.client }}
{{- end }}

{{/*
HTTP monitoring endpoint (host:port form, no scheme). KEDA's
nats-jetstream trigger expects this exact shape.
*/}}
{{- define "pleme-nats.monitoringEndpoint" -}}
{{ include "pleme-nats.fullname" . }}.{{ .Release.Namespace }}.svc:{{ .Values.service.ports.monitoring }}
{{- end }}
