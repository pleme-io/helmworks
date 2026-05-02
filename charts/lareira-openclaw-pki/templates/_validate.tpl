{{/*
Defense-in-depth: reject the all-zero placeholder digest so unsubstituted
release values fail() at template render rather than at image-pull time.

The fedramp-high overlay in pleme-lib enforces the *shape* of an image
(`@sha256:...` or `:sha256:...`) but not its entropy — without this
check, the placeholder zeros render cleanly.
*/}}
{{- define "lareira-openclaw-pki.validate.digest" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $tag := default "" (dig "image" "tag" "" $sub) -}}
{{- $repoHasDigest := contains "@sha256:" (default "" (dig "image" "repository" "" $sub)) -}}
{{- if and (hasPrefix "sha256:0000000000000000" $tag) (not $repoHasDigest) -}}
{{- fail (printf "lareira-openclaw-pki: image.tag is the all-zero placeholder digest %q; CI must substitute a real digest at release time. See chart README." $tag) -}}
{{- end -}}
{{- if and (eq $tag "") (not $repoHasDigest) -}}
{{- fail "lareira-openclaw-pki: pleme-microservice.image.tag is empty and pleme-microservice.image.repository does not contain @sha256:; supply a digest-pinned image" -}}
{{- end -}}
{{- end -}}

{{/*
Tameshi attestation gate. At fedramp-high the entire openclaw deploy
must be tameshi-attested before sekiban admits it. We enforce the
chart-time half here:

  • compliance.overlays MUST contain fedramp-high
  • sekiban.enabled MUST be true
  • attestation.enabled MUST be true
  • attestation.{signature,certificationHash,complianceHash} MUST be
    non-empty (changesetHash is informational)

The signature itself is produced by forge at release time. An operator
deploying without forge has no signature to provide and therefore
cannot deploy compliantly — by design.

Escape hatch: set `compliance.enforce: false` in the
pleme-microservice values to bypass for migration runs ONLY. This
flag is logged in audit annotations and surfaced by sekiban as a
Degraded status.
*/}}
{{- define "lareira-openclaw-pki.validate.attestation" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $compliance := dig "compliance" dict $sub -}}
{{- $overlays := dig "overlays" list $compliance -}}
{{- /* Raw dig — `default` would coerce `false` → `true` because false is falsy. */ -}}
{{- $enforce := dig "enforce" true $compliance -}}
{{- $sekiban := .Values.sekiban -}}
{{- $attestation := dig "attestation" dict $sub -}}
{{- if and $enforce (has "fedramp-high" $overlays) -}}
  {{- if not (dig "enabled" false $sekiban) -}}
{{- fail "lareira-openclaw-pki: fedramp-high requires sekiban.enabled=true (admission gate); set compliance.enforce=false ONLY for documented migration runs" -}}
  {{- end -}}
  {{- if not (dig "enabled" false $attestation) -}}
{{- fail "lareira-openclaw-pki: fedramp-high requires pleme-microservice.attestation.enabled=true" -}}
  {{- end -}}
  {{- if eq (dig "signature" "" $attestation) "" -}}
{{- fail "lareira-openclaw-pki: fedramp-high requires pleme-microservice.attestation.signature; CI/forge injects this at release time. See docs/RELEASE-FLOW.md." -}}
  {{- end -}}
  {{- if eq (dig "certificationHash" "" $attestation) "" -}}
{{- fail "lareira-openclaw-pki: fedramp-high requires pleme-microservice.attestation.certificationHash" -}}
  {{- end -}}
  {{- if eq (dig "complianceHash" "" $attestation) "" -}}
{{- fail "lareira-openclaw-pki: fedramp-high requires pleme-microservice.attestation.complianceHash" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
