{{/*
Overlay: cmmc-l3
Source: CMMC v2.0 Level 3 (Cybersecurity Maturity Model Certification)
        + 32 CFR Part 170 (CMMC final rule, Oct 2024)

CMMC L3 = NIST 800-171 Rev 2 (110 controls) + 24 additional CMMC L3
practices from NIST 800-172. Required for DoD contractors handling
Controlled Unclassified Information (CUI). Effectively layers on top of
fedramp-moderate + DoD CC SRG IL4.

This overlay declares cmmc-l3 = fedramp-high + dod-il4 + supplychain.
The cascade through requires pulls in airgap-consumer (transitively from
dod-il4).
*/}}

{{- define "pleme-lib.overlay.cmmc-l3.requires" -}}fedramp-high,dod-il4,supplychain{{- end }}

{{- define "pleme-lib.overlay.cmmc-l3.controls" -}}
CMMC-L3,NIST-800-171-3.1.1,NIST-800-171-3.1.2,NIST-800-171-3.4.1,NIST-800-171-3.4.2,NIST-800-171-3.5.1,NIST-800-171-3.5.2,NIST-800-171-3.6.1,NIST-800-171-3.13.1,NIST-800-171-3.13.16,NIST-800-171-3.14.1,NIST-800-171-3.14.6,NIST-800-172-3.1.3e,NIST-800-172-3.13.4e,NIST-800-172-3.14.6e
{{- end }}

{{- define "pleme-lib.overlay.cmmc-l3.validate" -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- if eq $isWorkload "true" -}}
  {{- /* CMMC L3 specifically calls out integrity verification (3.14.1)
         which we map to mandatory cosign verification. The supplychain
         requires already enforces SBOM + cosign at moderate; here we
         additionally insist that supplychain.cosign.signatureRef
         non-empty value is present. */ -}}
  {{- $sc := (.Values.compliance).supplychain | default dict -}}
  {{- $cosign := $sc.cosign | default dict -}}
  {{- if not $cosign.signatureRef -}}
    {{- fail (printf "compliance: cmmc-l3 overlay requires compliance.supplychain.cosign.signatureRef (NIST 800-171 3.14.1, NIST 800-172 3.14.6e)") -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.cmmc-l3.annotations" -}}
compliance.pleme.io/overlay-cmmc-l3: "true"
pleme.io/cmmc-version: "v2.0"
pleme.io/cmmc-level: "3"
pleme.io/cmmc-final-rule: "32-cfr-170"
{{ end }}

{{- define "pleme-lib.overlay.cmmc-l3.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.cmmc-l3.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.cmmc-l3.manifestData" -}}
overlay-cmmc-l3: "true"
cmmc-version: "v2.0"
cmmc-level: "3"
{{ end }}

{{- define "pleme-lib.overlay.cmmc-l3.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.cmmc-l3.imagePullSecrets" -}}{{- end }}
{{- define "pleme-lib.overlay.cmmc-l3.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.cmmc-l3.gatekeeperConstraint" -}}{{- end }}
