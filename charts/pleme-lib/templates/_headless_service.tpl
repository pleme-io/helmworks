{{/*
pleme-lib: headless Service for StatefulSet workloads

Ported from a downstream pleme-lib fork (its mysql / redis / neo4j charts
depend on it): `pleme-lib.statefulset.serviceName` computes the StatefulSet's
governing Service name (default `<fullname>-headless`, matching the inline
default `pleme-lib.statefulset` already uses); `pleme-lib.headlessService`
renders that Service (clusterIP: None) for stable per-pod DNS. Ports mirror
`.Values.service.ports`, same shape as `pleme-lib.service`.
*/}}
{{- define "pleme-lib.statefulset.serviceName" -}}
{{- (.Values.statefulset).serviceName | default (printf "%s-headless" (include "pleme-lib.fullname" .)) -}}
{{- end }}

{{- define "pleme-lib.headlessService" -}}
{{- $svc := .Values.service | default dict -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "pleme-lib.statefulset.serviceName" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- $resAnnotations := include "pleme-lib.resourceAnnotations" . }}
  {{- if $resAnnotations }}
  annotations:
    {{- $resAnnotations | nindent 4 }}
  {{- end }}
spec:
  type: ClusterIP
  clusterIP: None
  {{- with $svc.ports }}
  ports:
    {{- range . }}
    - name: {{ .name }}
      port: {{ .port }}
      targetPort: {{ .targetPort }}
      protocol: {{ .protocol | default "TCP" }}
    {{- end }}
  {{- end }}
  selector:
    {{- include "pleme-lib.selectorLabels" . | nindent 4 }}
{{- end }}
