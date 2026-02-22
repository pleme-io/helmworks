{{/*
pleme-lib: security context templates

Enforces a hardened security baseline across all pleme-io services.
These match the k8s-fluxcd-kaizen P0/P1 gates.
*/}}

{{/*
Pod security context
*/}}
{{- define "pleme-lib.podSecurityContext" -}}
runAsNonRoot: {{ .Values.podSecurityContext.runAsNonRoot | default true }}
runAsUser: {{ .Values.podSecurityContext.runAsUser | default 1000 }}
{{- with .Values.podSecurityContext.runAsGroup }}
runAsGroup: {{ . }}
{{- end }}
fsGroup: {{ .Values.podSecurityContext.fsGroup | default 1000 }}
{{- with .Values.podSecurityContext.seccompProfile }}
seccompProfile:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Container security context (enforced baseline)
*/}}
{{- define "pleme-lib.containerSecurityContext" -}}
allowPrivilegeEscalation: {{ .Values.securityContext.allowPrivilegeEscalation | default false }}
readOnlyRootFilesystem: {{ .Values.securityContext.readOnlyRootFilesystem | default true }}
capabilities:
  drop:
    {{- if .Values.securityContext.capabilities }}
    {{- toYaml .Values.securityContext.capabilities.drop | nindent 4 }}
    {{- else }}
    - ALL
    {{- end }}
{{- with .Values.securityContext.seccompProfile }}
seccompProfile:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
