{{/*
pleme-lib: configmap named template

Renders one ConfigMap per entry in .Values.configMaps[].
Each entry supports: name, data, labels, annotations.
*/}}

{{- define "pleme-lib.configmaps" -}}
{{- $fullname := include "pleme-lib.fullname" . -}}
{{- range .Values.configMaps }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .name | default (printf "%s-config" $fullname) }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
    {{- with .labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
data:
  {{- toYaml .data | nindent 2 }}
{{- end }}
{{- end }}
