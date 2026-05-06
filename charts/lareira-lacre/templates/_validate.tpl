{{/*
Defense-in-depth: reject the all-zero placeholder digest.
*/}}
{{- define "lareira-lacre.validate.digest" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $tag := default "" (dig "image" "tag" "" $sub) -}}
{{- $repoHasDigest := contains "@sha256:" (default "" (dig "image" "repository" "" $sub)) -}}
{{- if and (hasPrefix "sha256:0000000000000000" $tag) (not $repoHasDigest) -}}
{{- fail (printf "lareira-lacre: image.tag is the all-zero placeholder digest %q; CI must substitute a real digest at release time. See chart README." $tag) -}}
{{- end -}}
{{- if and (eq $tag "") (not $repoHasDigest) -}}
{{- fail "lareira-lacre: pleme-microservice.image.tag is empty and pleme-microservice.image.repository does not contain @sha256:" -}}
{{- end -}}
{{- end -}}

{{/*
Tameshi attestation gate. fedramp-high requires sekiban + attestation
fully populated. Same shape as openclaw-pki/cartorio/store/scanner.
*/}}
{{- define "lareira-lacre.validate.attestation" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $compliance := dig "compliance" dict $sub -}}
{{- $overlays := dig "overlays" list $compliance -}}
{{- $enforce := dig "enforce" true $compliance -}}
{{- $sekiban := .Values.sekiban -}}
{{- $attestation := dig "attestation" dict $sub -}}
{{- if and $enforce (has "fedramp-high" $overlays) -}}
  {{- if not (dig "enabled" false $sekiban) -}}
{{- fail "lareira-lacre: fedramp-high requires sekiban.enabled=true" -}}
  {{- end -}}
  {{- if not (dig "enabled" false $attestation) -}}
{{- fail "lareira-lacre: fedramp-high requires pleme-microservice.attestation.enabled=true" -}}
  {{- end -}}
  {{- if eq (dig "signature" "" $attestation) "" -}}
{{- fail "lareira-lacre: fedramp-high requires pleme-microservice.attestation.signature; CI/forge injects this at release time" -}}
  {{- end -}}
  {{- if eq (dig "certificationHash" "" $attestation) "" -}}
{{- fail "lareira-lacre: fedramp-high requires pleme-microservice.attestation.certificationHash" -}}
  {{- end -}}
  {{- if eq (dig "complianceHash" "" $attestation) "" -}}
{{- fail "lareira-lacre: fedramp-high requires pleme-microservice.attestation.complianceHash" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
