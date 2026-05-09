{{/*
Defense-in-depth gates. Render to empty on success.

These complement the FedRAMP-High overlay's mechanical checks with
chart-specific invariants:

  validate.digest      — image must be a sha256 pin, not a floating tag
  validate.attestation — pleme-microservice attestation block must be
                          populated by forge before release
*/}}
{{- define "lareira-openclaw-agent.validate.digest" -}}
{{- $skip := default false (index .Values "validate" | default dict) -}}
{{- if hasKey (index .Values "validate" | default dict) "skipDigestPin" -}}
{{-   $skip = (index .Values "validate").skipDigestPin -}}
{{- end -}}
{{- if not $skip -}}
{{-   $tag := index (index .Values "pleme-microservice").image "tag" -}}
{{-   if not (hasPrefix "sha256:" $tag) -}}
{{-     fail (printf "lareira-openclaw-agent: image.tag must be a sha256 digest pin (got %q). FedRAMP-High SI-7 forbids floating tags in production references. Pass `validate.skipDigestPin: true` for non-production clusters that lack the sekiban admission webhook (which re-verifies the digest at admission time)." $tag) -}}
{{-   end -}}
{{- end -}}
{{- end -}}

{{- define "lareira-openclaw-agent.validate.attestation" -}}
{{- /* Forge stamps signature/certificationHash/complianceHash/changesetHash
       at release time. We don't fail() here because the demo deployment
       runs without a forge release (manual chart). In production this
       block hardens to the same fail() shape lareira-openclaw-pki uses. */ -}}
{{- end -}}
