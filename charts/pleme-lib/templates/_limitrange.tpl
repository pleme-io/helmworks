{{/*
pleme-lib: limitrange named template

Container defaults/max/min, Pod max, PVC max/min.
*/}}

{{- define "pleme-lib.limitrange" -}}
{{- if (.Values.limitRange).enabled }}
apiVersion: v1
kind: LimitRange
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  limits:
    {{- if (.Values.limitRange).container }}
    - type: Container
      {{- with (.Values.limitRange).container.default }}
      default:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (.Values.limitRange).container.defaultRequest }}
      defaultRequest:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (.Values.limitRange).container.max }}
      max:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (.Values.limitRange).container.min }}
      min:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
    {{- if (.Values.limitRange).pod }}
    - type: Pod
      {{- with (.Values.limitRange).pod.max }}
      max:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (.Values.limitRange).pod.min }}
      min:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
    {{- if (.Values.limitRange).pvc }}
    - type: PersistentVolumeClaim
      {{- with (.Values.limitRange).pvc.max }}
      max:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (.Values.limitRange).pvc.min }}
      min:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
{{- end }}
{{- end }}
