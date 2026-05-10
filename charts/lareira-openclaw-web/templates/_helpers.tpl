{{- define "openclaw-web.fullname" -}}
{{- printf "%s-openclaw-web" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openclaw-web.labels" -}}
app.kubernetes.io/name: openclaw-web
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{/*
  Sanitize image.tag for the version label. K8s labels must be ≤63 chars
  and may not contain `:`. Sha256 digests violate both ("sha256:<64-hex>" =
  71 chars + colon). When the tag is a sha256 digest we record the first
  12 hex chars of the encoded portion (matches the docker UI convention);
  for normal tags we use the tag verbatim, truncated to 63 chars.
*/}}
app.kubernetes.io/version: {{ if hasPrefix "sha256:" .Values.image.tag }}{{ trunc 12 (trimPrefix "sha256:" .Values.image.tag) | quote }}{{ else }}{{ .Values.image.tag | trunc 63 | quote }}{{ end }}
pleme.io/part-of: openclaw
{{- end -}}

{{- define "openclaw-web.selectorLabels" -}}
app.kubernetes.io/name: openclaw-web
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
