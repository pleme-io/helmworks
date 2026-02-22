{{/*
pleme-lib: horizontalpodautoscaler named template
*/}}

{{- define "pleme-lib.hpa" -}}
{{- if (.Values.autoscaling).enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "pleme-lib.fullname" . }}
  minReplicas: {{ (.Values.autoscaling).minReplicas | default 1 }}
  maxReplicas: {{ (.Values.autoscaling).maxReplicas | default 5 }}
  metrics:
    {{- if (.Values.autoscaling).targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ (.Values.autoscaling).targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if (.Values.autoscaling).targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ (.Values.autoscaling).targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end }}
{{- end }}
