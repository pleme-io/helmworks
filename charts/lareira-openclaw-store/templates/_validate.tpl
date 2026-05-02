{{/*
Defense-in-depth: reject the all-zero placeholder digest.
*/}}
{{- define "lareira-openclaw-store.validate.digest" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $tag := default "" (dig "image" "tag" "" $sub) -}}
{{- $repoHasDigest := contains "@sha256:" (default "" (dig "image" "repository" "" $sub)) -}}
{{- if and (hasPrefix "sha256:0000000000000000" $tag) (not $repoHasDigest) -}}
{{- fail (printf "lareira-openclaw-store: image.tag is the all-zero placeholder digest %q; CI must substitute a real digest at release time. See chart README." $tag) -}}
{{- end -}}
{{- if and (eq $tag "") (not $repoHasDigest) -}}
{{- fail "lareira-openclaw-store: pleme-microservice.image.tag is empty and pleme-microservice.image.repository does not contain @sha256:; supply a digest-pinned image" -}}
{{- end -}}
{{- end -}}

{{/*
Reject postgres backend without a host (catches forgotten secret wiring).
*/}}
{{- define "lareira-openclaw-store.validate.persistence" -}}
{{- if eq .Values.persistence.backend "postgres" -}}
{{- if eq (default "" .Values.persistence.postgres.host) "" -}}
{{- fail "lareira-openclaw-store: persistence.backend=postgres requires persistence.postgres.host" -}}
{{- end -}}
{{- if eq (default "" .Values.persistence.postgres.secretRef.name) "" -}}
{{- fail "lareira-openclaw-store: persistence.backend=postgres requires persistence.postgres.secretRef.name" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Tameshi attestation gate (mirrors lareira-openclaw-pki).
*/}}
{{- define "lareira-openclaw-store.validate.attestation" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $compliance := dig "compliance" dict $sub -}}
{{- $overlays := dig "overlays" list $compliance -}}
{{- $enforce := dig "enforce" true $compliance -}}
{{- $sekiban := .Values.sekiban -}}
{{- $attestation := dig "attestation" dict $sub -}}
{{- if and $enforce (has "fedramp-high" $overlays) -}}
  {{- if not (dig "enabled" false $sekiban) -}}
{{- fail "lareira-openclaw-store: fedramp-high requires sekiban.enabled=true" -}}
  {{- end -}}
  {{- if not (dig "enabled" false $attestation) -}}
{{- fail "lareira-openclaw-store: fedramp-high requires pleme-microservice.attestation.enabled=true" -}}
  {{- end -}}
  {{- if eq (dig "signature" "" $attestation) "" -}}
{{- fail "lareira-openclaw-store: fedramp-high requires pleme-microservice.attestation.signature; CI/forge injects this at release time" -}}
  {{- end -}}
  {{- if eq (dig "certificationHash" "" $attestation) "" -}}
{{- fail "lareira-openclaw-store: fedramp-high requires pleme-microservice.attestation.certificationHash" -}}
  {{- end -}}
  {{- if eq (dig "complianceHash" "" $attestation) "" -}}
{{- fail "lareira-openclaw-store: fedramp-high requires pleme-microservice.attestation.complianceHash" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
