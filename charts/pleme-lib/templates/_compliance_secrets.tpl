{{/*
pleme-lib: compliance — secrets handling primitives

Maps to NIST 800-53 controls:
  IA-5  — Authenticator Management: secrets must be Secret-referenced, never
          inline literal values in env/podSpec
  SC-12 — Cryptographic Key Management: keys via external secret store
          (Borealis target -> ExternalSecret -> Secret), never hand-typed

At moderate+, every entry in .Values.env that has a name matching the
pattern *(SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY|CREDENTIAL)* MUST be
sourced via valueFrom.secretKeyRef, not via a literal `value:` field.

This is a heuristic — it cannot catch every secret-named variable, but it
catches the obvious foot-guns. Workloads that legitimately need a literal
value with a sensitive-looking name must rename or use the explicit
`compliance.secrets.allowLiteral: ["VAR_NAME"]` allowlist.
*/}}

{{- define "pleme-lib.compliance.secrets.validate" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- if eq $atLeastMod "true" -}}
  {{- $allowList := ((.Values.compliance).secrets).allowLiteral | default list -}}
  {{- $pattern := "(?i)(SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY|CREDENTIAL|PASSPHRASE)" -}}
  {{- range $idx, $entry := .Values.env | default list -}}
    {{- $name := $entry.name | default "" | toString -}}
    {{- if and $name (regexMatch $pattern $name) -}}
      {{- if hasKey $entry "value" -}}
        {{- if not (has $name $allowList) -}}
          {{- fail (printf "compliance: baseline >= fedramp-moderate forbids literal value for secret-shaped env var %q (IA-5, SC-12); use valueFrom.secretKeyRef, or add to compliance.secrets.allowLiteral if intentional" $name) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
