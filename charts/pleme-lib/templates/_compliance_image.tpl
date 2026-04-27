{{/*
pleme-lib: compliance — image / supply chain primitives

Maps to NIST 800-53 controls:
  CM-2  — Baseline Configuration: an image identified by a digest is a baseline,
          a tag is not. The same `latest` tag points at different bytes over time.
  SI-7  — Software Integrity: digest = cryptographic commitment to bytes.
  CM-7  — Least Functionality: pullPolicy=Always at moderate+ to ensure the
          digest is re-resolved each time and not pulled from a stale node cache
          that escaped attestation.

The template-time `fail` here is the most important "compliant primitive"
mechanism: at moderate+, you cannot accidentally ship a tag-pinned image.
*/}}

{{/*
Whether the image reference is digest-pinned (image@sha256:...).
Returns "true" / "false".
*/}}
{{- define "pleme-lib.compliance.image.isDigest" -}}
{{- $img := .Values.image | default dict -}}
{{- $tag := $img.tag | default "" | toString -}}
{{- $repo := $img.repository | default "" | toString -}}
{{- $digest := $img.digest | default "" | toString -}}
{{- if or (hasPrefix "sha256:" $tag) (contains "@sha256:" $repo) (hasPrefix "sha256:" $digest) -}}
true
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
Default pullPolicy under compliance.
At moderate+, pullPolicy must be Always (CM-7) so the digest is re-resolved
on every pod start and stale node-cached layers cannot drift the deployment.
*/}}
{{- define "pleme-lib.compliance.image.pullPolicy" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $img := .Values.image | default dict -}}
{{- if eq $atLeastMod "true" -}}
{{- $img.pullPolicy | default "Always" -}}
{{- else -}}
{{- $img.pullPolicy | default "IfNotPresent" -}}
{{- end -}}
{{- end }}

{{/*
Validate image invariants. No-op when .Values.image.repository is empty —
this lets pure-namespace / pure-policy charts (pleme-compliance,
pleme-namespace) call pleme-lib.compliance.validate without owning a
container image.
*/}}
{{- define "pleme-lib.compliance.image.validate" -}}
{{- $img := .Values.image | default dict -}}
{{- $repo := $img.repository | default "" | toString -}}
{{- if eq $repo "" -}}
  {{/* No image owned by this chart; image validation is not applicable. */}}
{{- else -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $tag := $img.tag | default "" | toString -}}
{{- $isDigest := include "pleme-lib.compliance.image.isDigest" . -}}
{{- if eq $atLeastMod "true" -}}
  {{/* Case-insensitive: `Latest`, `LATEST`, `lATesT` are equivalent
       under OCI tag conventions. Trim whitespace to catch ` latest `. */}}
  {{- $tagNorm := lower (trim $tag) -}}
  {{- if eq $tagNorm "latest" -}}
    {{- fail (printf "compliance: baseline=%s forbids image.tag=latest (CM-2, SI-7); use a digest like sha256:... or a content-addressed tag (case-insensitive: input=%q)" $b $tag) -}}
  {{- end -}}
  {{- $pp := include "pleme-lib.compliance.image.pullPolicy" . -}}
  {{- if eq $pp "Never" -}}
    {{- fail (printf "compliance: baseline=%s forbids image.pullPolicy=Never (CM-7)" $b) -}}
  {{- end -}}
  {{/* Forbid the ambiguous shape: repo contains @sha256:... AND tag is set.
       This silently makes tag a no-op and is a foot-gun for the consumer. */}}
  {{- $repo := $img.repository | toString -}}
  {{- if and (contains "@sha256:" $repo) (and (ne $tag "") (ne $tag "latest")) -}}
    {{- fail (printf "compliance: baseline=%s rejects ambiguous image: repository=%q already contains a digest, but image.tag=%q is also set; pick one form (CM-2)" $b $repo $tag) -}}
  {{- end -}}
{{- end -}}
{{- if eq $atLeastHigh "true" -}}
  {{- if eq $isDigest "false" -}}
    {{- fail (printf "compliance: baseline=%s requires image to be digest-pinned (CM-2, SI-7); set image.tag=sha256:... or use image@sha256:... in repository, current tag=%q" $b $tag) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
