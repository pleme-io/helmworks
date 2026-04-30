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
{{/*
  fsGroup is OPT-IN on the non-compliance baseline. K8s applies
  fsGroup as the group owner on every projected/secret volume mount
  AND adds g+r to the file mode bits — even when defaultMode is set
  explicitly. That breaks workloads like garage that refuse to start
  with group-readable secret files. Charts that genuinely need
  fsGroup (e.g. multi-container pods with shared writable volumes)
  set Values.podSecurityContext.fsGroup explicitly; charts that
  don't (the common case) leave it unset and avoid the mode-bit
  overlay. The compliance baseline still requires fsGroup; that
  path emits it via `pleme-lib.compliance.podSecurityContext`.
*/}}
{{- with (.Values.podSecurityContext).fsGroup }}
fsGroup: {{ . }}
{{- end }}
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
