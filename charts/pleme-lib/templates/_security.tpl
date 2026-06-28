{{/*
pleme-lib: security context templates

Enforces a hardened security baseline across all pleme-io services.
These match the k8s-fluxcd-kaizen P0/P1 gates.

Even with no compliance baseline, the default pod/container security context
now emits seccompProfile=RuntimeDefault, so workloads are PodSecurity
`restricted`-admissible out of the box. Override via
podSecurityContext.seccompProfile / securityContext.seccompProfile.

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
{{- $psc := .Values.podSecurityContext | default dict -}}
{{- /* hasKey (not `| default`): `| default` treats 0 / false as "empty" and
       coerces them back to the default, so a deliberate root workload
       (runAsNonRoot: false, runAsUser: 0) could not be expressed. */ -}}
runAsNonRoot: {{ if hasKey $psc "runAsNonRoot" }}{{ $psc.runAsNonRoot }}{{ else }}true{{ end }}
runAsUser: {{ if hasKey $psc "runAsUser" }}{{ $psc.runAsUser }}{{ else }}1000{{ end }}
{{- with $psc.runAsGroup }}
runAsGroup: {{ . }}
{{- end }}
fsGroup: {{ if hasKey $psc "fsGroup" }}{{ $psc.fsGroup }}{{ else }}1000{{ end }}
seccompProfile:
  type: {{ ($psc.seccompProfile).type | default "RuntimeDefault" }}
  {{- with ($psc.seccompProfile).localhostProfile }}
  localhostProfile: {{ . }}
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
{{- $sc := .Values.securityContext | default dict -}}
{{- /* hasKey for readOnlyRootFilesystem: `false | default true` -> true,
       so an explicit readOnlyRootFilesystem: false (e.g. a workload that
       must rewrite /etc at startup) was silently forced back to true. */ -}}
allowPrivilegeEscalation: {{ if hasKey $sc "allowPrivilegeEscalation" }}{{ $sc.allowPrivilegeEscalation }}{{ else }}false{{ end }}
readOnlyRootFilesystem: {{ if hasKey $sc "readOnlyRootFilesystem" }}{{ $sc.readOnlyRootFilesystem }}{{ else }}true{{ end }}
{{- if hasKey $sc "privileged" }}
privileged: {{ $sc.privileged }}
{{- end }}
{{- if hasKey $sc "runAsNonRoot" }}
runAsNonRoot: {{ $sc.runAsNonRoot }}
{{- end }}
capabilities:
  drop:
    {{- if and $sc.capabilities $sc.capabilities.drop }}
    {{- toYaml $sc.capabilities.drop | nindent 4 }}
    {{- else }}
    - ALL
    {{- end }}
  {{- /* capabilities.add is now values-driven at every baseline (the
         compliance variant already honored it; the legacy non-compliance
         branch silently dropped it). */ -}}
  {{- if and $sc.capabilities $sc.capabilities.add }}
  add:
    {{- toYaml $sc.capabilities.add | nindent 4 }}
  {{- end }}
seccompProfile:
  type: {{ ($sc.seccompProfile).type | default "RuntimeDefault" }}
  {{- with ($sc.seccompProfile).localhostProfile }}
  localhostProfile: {{ . }}
  {{- end }}
{{- end -}}
{{- end }}
