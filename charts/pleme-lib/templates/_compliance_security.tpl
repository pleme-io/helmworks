{{/*
pleme-lib: compliance — pod / container security primitives

Maps to NIST 800-53 controls:
  CM-6  — Configuration Settings: PSS-restricted enforcement
  CM-7  — Least Functionality: drop ALL capabilities, no privilege escalation
  AC-6  — Least Privilege: runAsNonRoot, automount=false, no host namespaces
  SC-39 — Process Isolation: seccompProfile=RuntimeDefault, readOnlyRootFilesystem
  SI-7  — Software / Information Integrity: image digest enforcement (see _compliance_image.tpl)
*/}}

{{/*
Pod-level securityContext for compliant workloads.

Baseline-driven defaults:
  - low / moderate / high: runAsNonRoot=true, runAsUser/Group/fsGroup default to 1000
  - moderate / high: seccompProfile=RuntimeDefault (CM-6, SC-39)
  - high: runAsUser/Group/fsGroup default to 65534 (nobody) unless explicitly set,
          fsGroupChangePolicy=OnRootMismatch to bound write surface

Consumer can still set podSecurityContext.* fields; compliance defaults only fill
gaps. Enforced invariants (runAsNonRoot=true, no privileged) are validated by
pleme-lib.compliance.security.validate.
*/}}
{{- define "pleme-lib.compliance.podSecurityContext" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $userDefaultUid := 1000 -}}
{{- if eq $atLeastHigh "true" }}{{ $userDefaultUid = 65534 }}{{ end }}
{{- $psc := .Values.podSecurityContext | default dict -}}
runAsNonRoot: {{ $psc.runAsNonRoot | default true }}
runAsUser: {{ $psc.runAsUser | default $userDefaultUid }}
runAsGroup: {{ $psc.runAsGroup | default $userDefaultUid }}
fsGroup: {{ $psc.fsGroup | default $userDefaultUid }}
{{- if eq $atLeastHigh "true" }}
fsGroupChangePolicy: {{ $psc.fsGroupChangePolicy | default "OnRootMismatch" }}
{{- end }}
{{- if eq $atLeastMod "true" }}
seccompProfile:
  type: {{ ($psc.seccompProfile).type | default "RuntimeDefault" }}
  {{- with ($psc.seccompProfile).localhostProfile }}
  localhostProfile: {{ . }}
  {{- end }}
{{- else }}
{{- with $psc.seccompProfile }}
seccompProfile:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- with $psc.supplementalGroups }}
supplementalGroups:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Container-level securityContext.

Mandated at every baseline:
  allowPrivilegeEscalation: false   — CM-7, AC-6
  readOnlyRootFilesystem:   true    — SI-7, CM-7
  capabilities.drop:        [ALL]   — CM-7

Mandated at moderate+:
  seccompProfile.type:      RuntimeDefault — SC-39, CM-6

Mandated at high:
  runAsNonRoot:             true    — AC-6
  privileged:               false   — CM-7 (forbidden)
*/}}
{{- define "pleme-lib.compliance.containerSecurityContext" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $sc := .Values.securityContext | default dict -}}
allowPrivilegeEscalation: {{ $sc.allowPrivilegeEscalation | default false }}
readOnlyRootFilesystem: {{ $sc.readOnlyRootFilesystem | default true }}
privileged: {{ $sc.privileged | default false }}
{{- if eq $atLeastHigh "true" }}
runAsNonRoot: {{ $sc.runAsNonRoot | default true }}
{{- end }}
capabilities:
  drop:
    {{- if and $sc.capabilities $sc.capabilities.drop }}
    {{- toYaml $sc.capabilities.drop | nindent 4 }}
    {{- else }}
    - ALL
    {{- end }}
  {{- if and $sc.capabilities $sc.capabilities.add }}
  add:
    {{- toYaml $sc.capabilities.add | nindent 4 }}
  {{- end }}
{{- if eq $atLeastMod "true" }}
seccompProfile:
  type: {{ ($sc.seccompProfile).type | default "RuntimeDefault" }}
  {{- with ($sc.seccompProfile).localhostProfile }}
  localhostProfile: {{ . }}
  {{- end }}
{{- else }}
{{- with $sc.seccompProfile }}
seccompProfile:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Whether to automount the ServiceAccount token. At moderate+, defaults to false
to satisfy AC-6 (least privilege). Workloads that genuinely need the token
must set automountServiceAccountToken: true explicitly in values, opting out
of the default and accepting the documented risk.
*/}}
{{- define "pleme-lib.compliance.automountServiceAccountToken" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- if hasKey .Values "automountServiceAccountToken" }}
{{- .Values.automountServiceAccountToken }}
{{- else if eq $atLeastMod "true" -}}
false
{{- else -}}
true
{{- end -}}
{{- end }}

{{/*
Validate hard security invariants.
Fails the template if the selected baseline forbids what values request.
*/}}
{{- define "pleme-lib.compliance.security.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $sc := .Values.securityContext | default dict -}}
{{- $psc := .Values.podSecurityContext | default dict -}}
{{- if eq $atLeastMod "true" -}}
  {{- if and (hasKey $sc "privileged") (eq (toString $sc.privileged) "true") -}}
    {{- fail (printf "compliance: baseline=%s forbids securityContext.privileged=true (CM-7)" $b) -}}
  {{- end -}}
  {{- if and (hasKey $sc "allowPrivilegeEscalation") (eq (toString $sc.allowPrivilegeEscalation) "true") -}}
    {{- fail (printf "compliance: baseline=%s forbids securityContext.allowPrivilegeEscalation=true (CM-7, AC-6)" $b) -}}
  {{- end -}}
  {{- if and (hasKey $sc "readOnlyRootFilesystem") (eq (toString $sc.readOnlyRootFilesystem) "false") -}}
    {{- fail (printf "compliance: baseline=%s requires securityContext.readOnlyRootFilesystem=true (SI-7)" $b) -}}
  {{- end -}}
  {{- if .Values.hostNetwork -}}
    {{- fail (printf "compliance: baseline=%s forbids hostNetwork=true (AC-6, SC-7)" $b) -}}
  {{- end -}}
  {{- if .Values.hostPID -}}
    {{- fail (printf "compliance: baseline=%s forbids hostPID=true (AC-6, CM-7)" $b) -}}
  {{- end -}}
  {{- if .Values.hostIPC -}}
    {{- fail (printf "compliance: baseline=%s forbids hostIPC=true (AC-6, CM-7)" $b) -}}
  {{- end -}}
  {{- if and $sc.capabilities $sc.capabilities.add -}}
    {{- $forbidden := list "SYS_ADMIN" "SYS_PTRACE" "SYS_MODULE" "SYS_RAWIO" "NET_ADMIN" "NET_RAW" "DAC_READ_SEARCH" "BPF" "ALL" -}}
    {{- range $sc.capabilities.add -}}
      {{- if has . $forbidden -}}
        {{- fail (printf "compliance: baseline=%s forbids capabilities.add=%s (CM-7, AC-6)" $b .) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if and $sc.seccompProfile (eq (toString $sc.seccompProfile.type) "Unconfined") -}}
    {{- fail (printf "compliance: baseline=%s forbids seccompProfile.type=Unconfined (CM-6, SI-16); use RuntimeDefault or Localhost" $b) -}}
  {{- end -}}
  {{- if and $psc.seccompProfile (eq (toString $psc.seccompProfile.type) "Unconfined") -}}
    {{- fail (printf "compliance: baseline=%s forbids podSecurityContext.seccompProfile.type=Unconfined (CM-6, SI-16)" $b) -}}
  {{- end -}}
  {{- if and (hasKey .Values "automountServiceAccountToken") (eq (toString .Values.automountServiceAccountToken) "true") -}}
    {{- $allow := ((.Values.compliance).security).allowAutomountServiceAccountToken | default false -}}
    {{- if not $allow -}}
      {{- fail (printf "compliance: baseline=%s forbids automountServiceAccountToken=true (AC-6, IA-2); set compliance.security.allowAutomountServiceAccountToken=true to opt out with documented justification" $b) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if eq $atLeastHigh "true" -}}
  {{- if and (hasKey $psc "runAsNonRoot") (eq (toString $psc.runAsNonRoot) "false") -}}
    {{- fail (printf "compliance: baseline=%s requires podSecurityContext.runAsNonRoot=true (AC-6)" $b) -}}
  {{- end -}}
  {{- if and (hasKey $psc "runAsUser") (eq (toString $psc.runAsUser) "0") -}}
    {{- fail (printf "compliance: baseline=%s forbids runAsUser=0 (AC-6)" $b) -}}
  {{- end -}}
  {{- if and (hasKey $sc "runAsNonRoot") (eq (toString $sc.runAsNonRoot) "false") -}}
    {{- fail (printf "compliance: baseline=%s requires container securityContext.runAsNonRoot=true (AC-6)" $b) -}}
  {{- end -}}
  {{- if and (hasKey $sc "runAsUser") (eq (toString $sc.runAsUser) "0") -}}
    {{- fail (printf "compliance: baseline=%s forbids container runAsUser=0 (AC-6)" $b) -}}
  {{- end -}}
  {{- range .Values.volumes | default list -}}
    {{- if .hostPath -}}
      {{- fail (printf "compliance: baseline=%s forbids hostPath volumes (AC-6, CM-7); offending volume: %s" $b .name) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
