{{/*
Defense-in-depth: reject the all-zero placeholder digest.
*/}}
{{- define "lareira-openclaw-scanner.validate.digest" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $tag := default "" (dig "image" "tag" "" $sub) -}}
{{- $repoHasDigest := contains "@sha256:" (default "" (dig "image" "repository" "" $sub)) -}}
{{- if and (hasPrefix "sha256:0000000000000000" $tag) (not $repoHasDigest) -}}
{{- fail (printf "lareira-openclaw-scanner: image.tag is the all-zero placeholder digest %q; CI must substitute a real digest at release time." $tag) -}}
{{- end -}}
{{- if and (eq $tag "") (not $repoHasDigest) -}}
{{- fail "lareira-openclaw-scanner: pleme-microservice.image.tag is empty and pleme-microservice.image.repository does not contain @sha256:" -}}
{{- end -}}
{{- end -}}

{{/*
Reject scan intervals shorter than 60s (would hammer the store) or
longer than 86400s (drift detection too slow for fedramp-high SI-4).
*/}}
{{- define "lareira-openclaw-scanner.validate.interval" -}}
{{- $envs := index .Values "pleme-microservice" "env" | default list -}}
{{- range $envs -}}
  {{- if eq .name "SCAN_INTERVAL_SECS" -}}
    {{- $secs := atoi .value -}}
    {{- if lt $secs 60 -}}
{{- fail (printf "lareira-openclaw-scanner: SCAN_INTERVAL_SECS=%d is below the 60s minimum (would hammer the store)" $secs) -}}
    {{- end -}}
    {{- if gt $secs 86400 -}}
{{- fail (printf "lareira-openclaw-scanner: SCAN_INTERVAL_SECS=%d is above the 86400s (24h) maximum; drift detection latency would exceed fedramp-high SI-4 expectations" $secs) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Tameshi attestation gate (mirrors lareira-openclaw-pki).
*/}}
{{- define "lareira-openclaw-scanner.validate.attestation" -}}
{{- $sub := index .Values "pleme-microservice" -}}
{{- $compliance := dig "compliance" dict $sub -}}
{{- $overlays := dig "overlays" list $compliance -}}
{{- $enforce := dig "enforce" true $compliance -}}
{{- $sekiban := .Values.sekiban -}}
{{- $attestation := dig "attestation" dict $sub -}}
{{- if and $enforce (has "fedramp-high" $overlays) -}}
  {{- if not (dig "enabled" false $sekiban) -}}
{{- fail "lareira-openclaw-scanner: fedramp-high requires sekiban.enabled=true" -}}
  {{- end -}}
  {{- if not (dig "enabled" false $attestation) -}}
{{- fail "lareira-openclaw-scanner: fedramp-high requires pleme-microservice.attestation.enabled=true" -}}
  {{- end -}}
  {{- if eq (dig "signature" "" $attestation) "" -}}
{{- fail "lareira-openclaw-scanner: fedramp-high requires pleme-microservice.attestation.signature; CI/forge injects this at release time" -}}
  {{- end -}}
  {{- if eq (dig "certificationHash" "" $attestation) "" -}}
{{- fail "lareira-openclaw-scanner: fedramp-high requires pleme-microservice.attestation.certificationHash" -}}
  {{- end -}}
  {{- if eq (dig "complianceHash" "" $attestation) "" -}}
{{- fail "lareira-openclaw-scanner: fedramp-high requires pleme-microservice.attestation.complianceHash" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
