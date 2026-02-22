{{/*
pleme-lib: resourcequota named template

Namespace resource quotas for CPU, memory, pods, PVCs, services, configmaps, secrets.
*/}}

{{- define "pleme-lib.resourcequota" -}}
{{- if .Values.resourceQuota.enabled }}
apiVersion: v1
kind: ResourceQuota
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  hard:
    {{- toYaml .Values.resourceQuota.hard | nindent 4 }}
{{- end }}
{{- end }}
