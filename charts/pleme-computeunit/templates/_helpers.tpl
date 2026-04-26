{{/*
pleme-computeunit helpers — shared between every consumer chart.
*/}}

{{- define "pleme-computeunit.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pleme-computeunit.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: lareira
pleme.pleme.io/managed-via: helm
{{- end -}}

{{- define "pleme-computeunit.shape" -}}
{{- if .Values.trigger.oneShot -}}program{{- else if .Values.trigger.cron -}}job{{- else if .Values.trigger.service -}}service{{- else if .Values.trigger.event -}}function{{- else if .Values.trigger.watch -}}controller{{- else -}}invalid{{- end -}}
{{- end -}}

{{/*
Validate that exactly one trigger shape is set. Helm's tpl can't return
a hard error easily, so we check at render time and refuse to emit the
ComputeUnit if shape is invalid.
*/}}
{{- define "pleme-computeunit.validate-shape" -}}
{{- $shape := include "pleme-computeunit.shape" . -}}
{{- if eq $shape "invalid" -}}
{{- fail (printf "pleme-computeunit (%s): exactly one of trigger.{oneShot,cron,service,event,watch} must be set" .Release.Name) -}}
{{- end -}}
{{- end -}}
