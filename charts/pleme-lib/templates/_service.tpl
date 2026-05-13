{{/*
pleme-lib: service named template

Renders nothing when:
  - service.enabled is explicitly false (set this for headless workloads
    like one-shot jobs / bootstrap deployments / sidecar-only pods)
  - service.ports is empty (no exposable ports → no Service object)

Default behaviour (when neither is set) emits a Service with all the
declared ports.
*/}}

{{- define "pleme-lib.service" -}}
{{- $svc := .Values.service | default dict -}}
{{- $enabled := $svc.enabled -}}
{{- if and (hasKey $svc "enabled") (not $enabled) -}}
{{- /* service.enabled: false → emit nothing */ -}}
{{- else if not $svc.ports -}}
{{- /* no ports declared → emit nothing */ -}}
{{- else -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- $resAnnotations := include "pleme-lib.resourceAnnotations" . }}
  {{- if $resAnnotations }}
  annotations:
    {{- $resAnnotations | nindent 4 }}
  {{- end }}
spec:
  type: {{ $svc.type | default "ClusterIP" }}
  ports:
    {{- range $svc.ports }}
    - name: {{ .name }}
      port: {{ .port }}
      targetPort: {{ .targetPort }}
      protocol: {{ .protocol | default "TCP" }}
    {{- end }}
  selector:
    {{- include "pleme-lib.selectorLabels" . | nindent 4 }}
{{- end -}}
{{- end }}
