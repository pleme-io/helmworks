{{- define "openclaw-web.fullname" -}}
{{- printf "%s-openclaw-web" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openclaw-web.labels" -}}
app.kubernetes.io/name: openclaw-web
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
pleme.io/part-of: openclaw
{{- end -}}

{{- define "openclaw-web.selectorLabels" -}}
app.kubernetes.io/name: openclaw-web
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
