{{/*
lareira-pangea-platform helpers.

The chart renders four typed values lists into operator CRDs. Each helper
below is a small typed projection — a values element → one CRD document.
*/}}

{{/* Chart name (for app.kubernetes.io/name). */}}
{{- define "lareira-pangea-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels merged onto every rendered CR. Callers add per-CR labels
on top of this.
*/}}
{{- define "lareira-pangea-platform.labels" -}}
app.kubernetes.io/name: {{ include "lareira-pangea-platform.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
pleme.io/platform: pangea
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Namespace a NAMESPACED CR lands in.
Precedence: the CR's own `.namespace` → .Values.namespace → .Release.Namespace.
Usage: {{ include "lareira-pangea-platform.ns" (dict "cr" $cr "root" $) }}
*/}}
{{- define "lareira-pangea-platform.ns" -}}
{{- $cr := .cr -}}
{{- $root := .root -}}
{{- default (default $root.Release.Namespace $root.Values.namespace) $cr.namespace -}}
{{- end -}}
