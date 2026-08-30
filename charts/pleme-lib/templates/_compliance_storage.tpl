{{/*
pleme-lib: compliance — storage primitives

Maps to NIST 800-53 controls:
  SC-28 — Protection of Information at Rest: PVCs must use an encrypted
          storage class
  CM-7  — Least Functionality: hostPath volumes forbidden (already enforced
          in _compliance_security.tpl::security.validate)
  AU-11 — Audit Record Retention: persistent storage for audit data has
          retention guarantees (cluster-side, declared via annotation)

At fedramp-high, every PVC declared via .Values.persistence.* MUST have a
storageClassName from the .Values.compliance.storage.encryptedClasses
allowlist (default: any class name containing "encrypted" or "fips").
*/}}

{{- define "pleme-lib.compliance.storage.encryptedClasses" -}}
{{- $cs := ((.Values.compliance).storage) | default dict -}}
{{- if $cs.encryptedClasses -}}
{{- $cs.encryptedClasses | toJson -}}
{{- else -}}
["encrypted","encrypted-fast","encrypted-retain","fips-encrypted","csi-encrypted"]
{{- end -}}
{{- end }}

{{- define "pleme-lib.compliance.storage.validate" -}}
{{- /* The storage POSTURE (ephemeral|durable) is validated here too, so this
       stays the single storage validator entry point rather than two that a
       caller has to remember to call both of. It is baseline-INDEPENDENT and
       is therefore ALSO called ungated from _deployment.tpl / _statefulset.tpl;
       it is idempotent (a pure guard, emitting nothing), so calling it twice
       costs nothing. See _compliance_storage_posture.tpl. */ -}}
{{- include "pleme-lib.compliance.storage.posture.validate" . -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- if eq $atLeastHigh "true" -}}
  {{- $allowedJson := include "pleme-lib.compliance.storage.encryptedClasses" . -}}
  {{- $allowed := $allowedJson | fromJsonArray -}}
  {{- $persistence := .Values.persistence | default dict -}}
  {{- if eq (toString $persistence.enabled) "true" -}}
    {{- $sc := $persistence.storageClass | default $persistence.storageClassName | default "" | toString -}}
    {{- if eq $sc "" -}}
      {{- fail (printf "compliance: baseline=fedramp-high requires persistence.storageClass to be set to an encrypted class (SC-28); allowed: %v" $allowed) -}}
    {{- end -}}
    {{- if not (has $sc $allowed) -}}
      {{- $hasEncrypted := false -}}
      {{- range $allowed -}}
        {{- if eq . $sc }}{{ $hasEncrypted = true }}{{ end -}}
      {{- end -}}
      {{- if not $hasEncrypted -}}
        {{- fail (printf "compliance: baseline=fedramp-high requires persistence.storageClass=%q to be in the encrypted-class allowlist %v (SC-28); customize via compliance.storage.encryptedClasses" $sc $allowed) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
