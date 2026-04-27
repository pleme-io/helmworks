{{/*
pleme-lib: compliance — attestation primitives

Maps to NIST 800-53 controls:
  CM-2  — Baseline Configuration: tameshi BLAKE3 fingerprint of the chart
  SI-7  — Software, Firmware, Information Integrity: signature chain
  SC-12 — Cryptographic Key Management: hashes computed with BLAKE3, signed
          via Akeyless DFC (split-knowledge threshold) per tameshi
  AC-3  — Access Enforcement: sekiban admission webhook gates on these
          annotations; without them admission is denied

At fedramp-high, attestation.enabled MUST be true. This makes sekiban's
admission webhook the deployment-time enforcement of the proof chain
(arch-synthesizer typescape -> tameshi BLAKE3 -> signed root -> sekiban
ValidatingAdmissionWebhook).
*/}}

{{- define "pleme-lib.compliance.attestation.validate" -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- if eq $atLeastHigh "true" -}}
  {{- $att := .Values.attestation | default dict -}}
  {{/* Explicit toString comparison — `if not $att.enabled` bypasses on
       string "false" because non-empty strings are truthy in Sprig. */}}
  {{- if ne (toString $att.enabled) "true" -}}
    {{- fail (printf "compliance: baseline=fedramp-high requires attestation.enabled=true (CM-2, SI-7, AC-3); sekiban admission would be unable to verify integrity") -}}
  {{- end -}}
{{- end -}}
{{- end }}
