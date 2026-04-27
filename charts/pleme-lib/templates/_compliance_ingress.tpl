{{/*
pleme-lib: compliance — ingress / TLS primitives

Maps to NIST 800-53 controls:
  SC-8  — Transmission Confidentiality: external Ingress MUST terminate TLS
  SC-13 — Cryptographic Protection: TLS 1.2+ (cluster-policy concern, but
          chart-level we forbid plaintext Ingress entirely)
  AC-17 — Remote Access: external Ingress is the canonical remote access
          path; it must be encrypted

At moderate+, if .Values.ingress.enabled=true then .Values.ingress.tls
must be a non-empty list. Internal traffic remains clear-text-OK because
it's already inside the cluster trust boundary; egress to external services
is governed by compliance.network.allowTlsEgress.
*/}}

{{- define "pleme-lib.compliance.ingress.validate" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- if eq $atLeastMod "true" -}}
  {{- $ing := .Values.ingress | default dict -}}
  {{- if eq (toString $ing.enabled) "true" -}}
    {{- $tls := $ing.tls | default list -}}
    {{- if eq (len $tls) 0 -}}
      {{- fail (printf "compliance: baseline >= fedramp-moderate requires ingress.tls to be non-empty (SC-8, SC-13, AC-17); plaintext external Ingress is forbidden") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
