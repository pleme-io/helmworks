{{/*
pleme-lib: compliance — RBAC / identity primitives

Maps to NIST 800-53 controls:
  AC-3  — Access Enforcement: dedicated ServiceAccount per workload
  AC-6  — Least Privilege: no shared default SA; no cluster-admin Roles
  IA-2  — Identification & Authentication: SA tokens, projected only

At moderate+, every workload MUST have its own ServiceAccount (either created
by this chart or supplied externally and named explicitly). The "default" SA
is forbidden because it grants ambient namespace-level identity to anyone
who lands on it.
*/}}

{{- define "pleme-lib.compliance.rbac.validate" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- if eq $atLeastMod "true" -}}
  {{- $sa := .Values.serviceAccount | default dict -}}
  {{- $createSA := $sa.create | default false -}}
  {{- $name := $sa.name | default "" | toString -}}
  {{- if and (not $createSA) (or (eq $name "") (eq $name "default")) -}}
    {{- fail (printf "compliance: baseline >= fedramp-moderate requires a dedicated ServiceAccount (AC-3, AC-6, IA-2); set serviceAccount.create=true or supply serviceAccount.name=<non-default>") -}}
  {{- end -}}
{{- end -}}
{{- end }}
