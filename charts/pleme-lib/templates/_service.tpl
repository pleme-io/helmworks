{{/*
pleme-lib: service named template
*/}}

{{- define "pleme-lib.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  type: {{ (.Values.service).type | default "ClusterIP" }}
  ports:
    {{- range (.Values.service).ports }}
    - name: {{ .name }}
      port: {{ .port }}
      targetPort: {{ .targetPort }}
      protocol: {{ .protocol | default "TCP" }}
    {{- end }}
  selector:
    {{- include "pleme-lib.selectorLabels" . | nindent 4 }}
{{- end }}
