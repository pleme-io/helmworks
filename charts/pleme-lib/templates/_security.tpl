{{/*
pleme-lib: security context templates

Enforces a hardened security baseline across all pleme-io services.
These match the k8s-fluxcd-kaizen P0/P1 gates.

When `.Values.compliance.baseline` is set, the rendered security context is
produced by `_compliance_security.tpl` instead — that variant is baseline-aware
(seccompProfile, fsGroupChangePolicy, runAsUser policy) and validated.
*/}}

{{/*
Pod security context
*/}}
{{- define "pleme-lib.podSecurityContext" -}}
{{- $enabled := include "pleme-lib.compliance.enabled" . -}}
{{- if eq $enabled "true" -}}
{{- include "pleme-lib.compliance.podSecurityContext" . -}}
{{- else -}}
runAsNonRoot: {{ (.Values.podSecurityContext).runAsNonRoot | default true }}
runAsUser: {{ (.Values.podSecurityContext).runAsUser | default 1000 }}
{{- with (.Values.podSecurityContext).runAsGroup }}
runAsGroup: {{ . }}
{{- end }}
fsGroup: {{ (.Values.podSecurityContext).fsGroup | default 1000 }}
{{- with (.Values.podSecurityContext).seccompProfile }}
seccompProfile:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
{{- end }}

{{/*
Container security context (enforced baseline)
*/}}
{{- define "pleme-lib.containerSecurityContext" -}}
{{- $enabled := include "pleme-lib.compliance.enabled" . -}}
{{- if eq $enabled "true" -}}
{{- include "pleme-lib.compliance.containerSecurityContext" . -}}
{{- else -}}
allowPrivilegeEscalation: {{ (.Values.securityContext).allowPrivilegeEscalation | default false }}
readOnlyRootFilesystem: {{ (.Values.securityContext).readOnlyRootFilesystem | default true }}
capabilities:
  drop:
    {{- if (.Values.securityContext).capabilities }}
    {{- toYaml (.Values.securityContext).capabilities.drop | nindent 4 }}
    {{- else }}
    - ALL
    {{- end }}
{{- with (.Values.securityContext).seccompProfile }}
seccompProfile:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
{{- end }}
