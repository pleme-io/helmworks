{{/* The workload's name: `name`, or the release name. */}}
{{- define "engenho-unit.name" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" }}
{{- end }}
