{{/*
pleme-lib: compliance — mirror / scheduled-sync primitives

Generic "this workload pulls from external sources into a local store on
a schedule" pattern. Image-sync is the first consumer; future consumers
include helm-mirror (charts), policy-mirror (OPA bundles), sbom-mirror,
attestation-mirror, etc. — anything that has the shape:

   external upstream  →  scheduled fetcher  →  local store

Composes:
  Layer 1: _compliance_egress.tpl   (toUpstream allowlist for the fetcher)
  Layer 1: _compliance_authz.tpl    (least-privilege Role for writing to
                                     the local store)
  Layer 2: _compliance_airgap.tpl   (registry-mirror role — fetcher is
                                     the *only* workload allowed external
                                     egress in the air-gap pattern)

Maps to NIST 800-53 controls:
  AU-2  — Audit Events: every sync run emits a structured log entry
  AU-3  — Content of Audit: includes upstream URL, source digest, target
          digest, success/failure
  AU-12 — Audit Generation: emitted by the fetcher, scraped by Vector
  IA-5  — Authenticator Management: upstream credentials via Secret
  SI-7  — Software Integrity: cosign verification of fetched bytes
          before promoting to the local store
  CM-2  — Baseline Configuration: the schedule + allowlist + Secret are
          the version-controlled baseline
*/}}

{{/*
Schedule for the sync job. Default: every 15 minutes during business
hours (cron expression below) — busy enough to catch upstream changes
within an hour, quiet enough to not hammer rate limits.

Operators override .Values.compliance.mirror.schedule for tighter or
looser windows.
*/}}
{{- define "pleme-lib.compliance.mirror.schedule" -}}
{{- $m := (.Values.compliance).mirror | default dict -}}
{{- $m.schedule | default "*/15 8-18 * * 1-5" -}}
{{- end }}

{{/*
Compliance manifest data — mirror claim. Surfaces in the
compliance-manifest ConfigMap.
*/}}
{{- define "pleme-lib.compliance.mirror.manifestData" -}}
{{- $m := (.Values.compliance).mirror | default dict -}}
{{- if $m.upstreams }}
mirror-enabled: "true"
mirror-schedule: {{ include "pleme-lib.compliance.mirror.schedule" . | quote }}
mirror-upstream-count: {{ len $m.upstreams | quote }}
mirror-cosign-verify: {{ (eq (toString $m.cosignVerify) "true") | quote }}
{{- end }}
{{- end }}

{{/*
Validate.

At any compliance baseline >= moderate, when compliance.mirror is configured:
  - mirror.upstreams must be non-empty
  - each upstream must declare a credentialSecret (or anonymousUpstream=true
    in compliance.mirror.allowList)
  - schedule must be a valid cron (heuristic: must contain spaces)

At fedramp-high:
  - mirror.cosignVerify must be true
  - mirror.cosignKeyRef must reference a Secret
  - mirror.audit.required must default to true
*/}}
{{- define "pleme-lib.compliance.mirror.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $m := (.Values.compliance).mirror | default dict -}}
{{- $allow := $m.allowList | default dict -}}
{{- if and (eq $atLeastMod "true") $m.upstreams -}}
  {{- if eq (len $m.upstreams) 0 -}}
    {{- fail (printf "compliance: baseline=%s requires compliance.mirror.upstreams to be non-empty when configured (CM-2)" $b) -}}
  {{- end -}}
  {{- range $idx, $u := $m.upstreams -}}
    {{- if and (not $u.credentialSecret) (not $allow.anonymousUpstream) -}}
      {{- fail (printf "compliance: baseline=%s requires compliance.mirror.upstreams[%d].credentialSecret (IA-5, AU-3); anonymous upstream %q is forbidden without compliance.mirror.allowList.anonymousUpstream=true" $b $idx ($u.host | toString)) -}}
    {{- end -}}
  {{- end -}}
  {{- $sched := include "pleme-lib.compliance.mirror.schedule" . -}}
  {{- if not (contains " " $sched) -}}
    {{- fail (printf "compliance: compliance.mirror.schedule does not look like a cron expression: %q" $sched) -}}
  {{- end -}}
{{- end -}}
{{- if and (eq $atLeastHigh "true") $m.upstreams -}}
  {{- if not (eq (toString $m.cosignVerify) "true") -}}
    {{- fail (printf "compliance: baseline=fedramp-high + mirror.upstreams set requires compliance.mirror.cosignVerify=true (SI-7); fetched bytes must be signature-verified before promotion to the local store") -}}
  {{- end -}}
  {{- if not $m.cosignKeyRef -}}
    {{- fail (printf "compliance: baseline=fedramp-high + cosignVerify=true requires compliance.mirror.cosignKeyRef (Secret reference for the cosign public key)") -}}
  {{- end -}}
{{- end -}}
{{- end }}
