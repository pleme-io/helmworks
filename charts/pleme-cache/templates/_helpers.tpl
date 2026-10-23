{{/*
pleme-cache helpers — delegates to pleme-lib
*/}}

{{- define "pleme-cache.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-cache.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-cache.initDelivery" -}}
{{- if and .Values.cache.password.enabled (eq .Values.cache.password.delivery "init") }}true{{- end }}
{{- end }}
