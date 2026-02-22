{{/*
pleme-lib: shared helpers for all pleme-io charts
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "pleme-lib.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this.
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pleme-lib.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pleme-lib.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pleme-lib.labels" -}}
helm.sh/chart: {{ include "pleme-lib.chart" . }}
{{ include "pleme-lib.selectorLabels" . }}
app: {{ include "pleme-lib.fullname" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nexus-platform
{{- with .Values.additionalLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pleme-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pleme-lib.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "pleme-lib.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pleme-lib.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "pleme-lib.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Prometheus scrape annotations
*/}}
{{- define "pleme-lib.prometheusAnnotations" -}}
{{- if .Values.monitoring.enabled }}
prometheus.io/scrape: "true"
prometheus.io/port: {{ .Values.monitoring.port | default "8080" | quote }}
prometheus.io/path: {{ .Values.monitoring.path | default "/metrics" | quote }}
{{- end }}
{{- end }}

{{/*
Image string
*/}}
{{- define "pleme-lib.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default "latest") }}
{{- end }}

{{/*
Istio sidecar annotations for pod templates
*/}}
{{- define "pleme-lib.istioAnnotations" -}}
{{- if .Values.istio.enabled }}
sidecar.istio.io/inject: {{ .Values.istio.inject | default true | quote }}
{{- with .Values.istio.excludeOutboundPorts }}
traffic.sidecar.istio.io/excludeOutboundPorts: {{ . | quote }}
{{- end }}
{{- with .Values.istio.excludeInboundPorts }}
traffic.sidecar.istio.io/excludeInboundPorts: {{ . | quote }}
{{- end }}
{{- if .Values.istio.holdApplicationUntilProxyStarts }}
proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'
{{- end }}
{{- end }}
{{- end }}

{{/*
FluxCD prune disabled annotation — prevents FluxCD from deleting the resource
Used for StatefulSet VCTs, database CRs, cache PVCs.
*/}}
{{- define "pleme-lib.fluxcdPruneDisabled" -}}
kustomize.toolkit.fluxcd.io/prune: disabled
{{- end }}
