{{/*
pleme-lib: compliance primitives — entry points

Single source of truth for what "compliant" means at the chart layer.
Consumers set `.Values.compliance.baseline` to one of:

  ""               — no baseline (legacy; values control everything explicitly)
  "fedramp-low"    — NIST 800-53 Low baseline subset applicable to K8s workloads
  "fedramp-moderate" — Moderate baseline (default for prod workloads)
  "fedramp-high"   — High baseline (regulated workloads); strongest invariants

Selecting a baseline mechanically forces every other security/availability/
network/audit invariant on. Non-compliant value combinations cause a
template-time `fail` so a non-compliant chart never reaches the cluster.

The control catalog is defined in:
  pangea-architectures/lib/pangea/architectures/generated/compliance/fedramp_high.rb
  kensa/src/mapping/fedramp.rs (FedRAMP report catalog)
  tameshi/src/compliance/dimensions.rs (DimensionType::FedRamp)

This file's helpers are the K8s-workload mapping of those controls.
*/}}

{{/*
Active baseline. Returns "" or one of fedramp-low / fedramp-moderate / fedramp-high.

pleme-lib 0.9.0+: when `.Values.compliance.baseline` is unset, derive from
`.Values.compliance.overlays` (the canonical surface). This makes back-compat
bidirectional — legacy values synthesize an overlay list AND direct-overlay
declaration synthesizes a baseline so every existing helper that gates on
compliance.baseline works uniformly under both shapes.
*/}}
{{- define "pleme-lib.compliance.baseline" -}}
{{- $b := ((.Values.compliance | default dict).baseline | default "") | toString | lower | trim -}}
{{- if eq $b "" -}}
  {{- /* Read RESOLVED list (closure-expanded) so transitive requires
         (e.g. dod-il5 → fedramp-high → fedramp-moderate) are visible. */ -}}
  {{- $overlays := include "pleme-lib.overlay.list" . | fromYamlArray -}}
  {{- if has "fedramp-high" $overlays -}}fedramp-high
  {{- else if has "fedramp-moderate" $overlays -}}fedramp-moderate
  {{- else if has "fedramp-low" $overlays -}}fedramp-low
  {{- end -}}
{{- else -}}
{{- $b -}}
{{- end -}}
{{- end }}

{{/*
Returns "true" / "false" depending on whether the baseline is at-or-above
the threshold passed in. Threshold ordering:
  fedramp-low (1) < fedramp-moderate (2) < fedramp-high (3)

Usage: {{ if eq (include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate")) "true" }}
*/}}
{{- define "pleme-lib.compliance.atLeast" -}}
{{- $ctx := index . 0 -}}
{{- $threshold := index . 1 -}}
{{- $rank := dict "" 0 "fedramp-low" 1 "fedramp-moderate" 2 "fedramp-high" 3 -}}
{{- $cur := include "pleme-lib.compliance.baseline" $ctx -}}
{{- $curR := index $rank $cur | default 0 -}}
{{- $thrR := index $rank $threshold | default 0 -}}
{{- if ge ($curR | int) ($thrR | int) }}true{{ else }}false{{ end }}
{{- end }}

{{/*
Returns "true" if compliance is active. Active means any of:
  - compliance.baseline set (legacy)
  - compliance.overlays non-empty (canonical)
  - any legacy compliance.* opt-in (airgap.enabled, fips.enabled,
    supplychain.enabled, dod.impactLevel) — these synthesize an
    overlay list via the back-compat shim, so checking the resolved
    list catches them all uniformly.
*/}}
{{- define "pleme-lib.compliance.enabled" -}}
{{- $list := include "pleme-lib.overlay.list" . | fromYamlArray -}}
{{- if gt (len $list) 0 }}true{{ else }}false{{ end }}
{{- end }}

{{/*
Whether enforcement is on. Defaults to true when a baseline is selected;
can be set to false explicitly via `.Values.compliance.enforce` to allow
dry-runs (compliance metadata still rendered but `fail` validators skipped).
*/}}
{{- define "pleme-lib.compliance.enforce" -}}
{{- $enabled := include "pleme-lib.compliance.enabled" . }}
{{- if eq $enabled "true" }}
{{- if hasKey (.Values.compliance | default dict) "enforce" }}
{{- (.Values.compliance).enforce }}
{{- else }}true{{ end }}
{{- else }}false{{ end }}
{{- end }}

{{/*
NIST 800-53 controls covered by the workload primitives at this baseline.
Returned as a comma-separated string suitable for label/annotation values.

Coverage is derived from the K8s-mappable subset of:
  fedramp-low      → AU-2, AU-12, CM-2, CM-6, CM-7, IA-2, SC-7, SC-13
  fedramp-moderate → adds AC-3, AC-4, AC-6, AC-17, AU-3, AU-11, CM-8,
                     IA-5, SC-8, SC-12, SC-22, SI-4
  fedramp-high     → adds SC-5, SC-7(4), SC-7(5), SC-28, SI-7, SI-16
*/}}
{{/*
Controls list is now MECHANICALLY GENERATED from the overlay registry.
Each overlay declares its `controls` surface; the dispatcher joins them
with commas. Adding a new compliance regime (HIPAA, PCI-DSS, CMMC, …)
adds its controls to this list automatically — no central edit needed.

The proof of compliance composes:
  controls(overlays) = ⋃ {overlay.controls : overlay ∈ resolved(overlays)}
*/}}
{{- define "pleme-lib.compliance.controls" -}}
{{- include "pleme-lib.overlay.dispatchJoin" (list "controls" . ",") -}}
{{- end }}

{{/*
Compliance labels. Applied to every resource produced by pleme-lib.* helpers.
These labels make the cluster self-describe its compliance posture and let
Falco / Kubescape / sekiban filter by baseline.
*/}}
{{- define "pleme-lib.compliance.labels" -}}
{{- $enabled := include "pleme-lib.compliance.enabled" . -}}
{{- if eq $enabled "true" }}
compliance.pleme.io/baseline: {{ include "pleme-lib.compliance.baseline" . | quote }}
compliance.pleme.io/framework: "nist-800-53-rev5"
{{- end }}
{{- end }}

{{/*
Compliance annotations. Heavier-weight metadata: control coverage, attestation
hashes (sekiban), audit posture. Annotations are used over labels because:
  - control lists exceed the 63-char K8s label limit
  - sekiban.pleme.io/* annotations are read by the admission webhook
  - audit pipelines parse annotations for OSCAL evidence collection
*/}}
{{- define "pleme-lib.compliance.annotations" -}}
{{- $enabled := include "pleme-lib.compliance.enabled" . -}}
{{- if eq $enabled "true" }}
compliance.pleme.io/baseline: {{ include "pleme-lib.compliance.baseline" . | quote }}
compliance.pleme.io/controls: {{ include "pleme-lib.compliance.controls" . | quote }}
compliance.pleme.io/framework: "nist-800-53-rev5"
compliance.pleme.io/enforce: {{ include "pleme-lib.compliance.enforce" . | quote }}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") }}
{{- if eq $atLeastMod "true" }}
compliance.pleme.io/sekiban-required: "true"
compliance.pleme.io/audit-required: "true"
{{- end }}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") }}
{{- if eq $atLeastHigh "true" }}
compliance.pleme.io/availability-required: "true"
compliance.pleme.io/encryption-at-rest-required: "true"
{{- end }}
{{- end }}
{{- end }}

{{/*
Whether this Release renders a workload (Deployment/StatefulSet/Job/etc.).
Detected by the presence of a non-empty .Values.image.repository.

Used to gate workload-scoped validators (security context, audit, availability,
network, image) so that pure-policy charts (pleme-compliance, pleme-namespace)
which call pleme-lib.compliance.validate from their templates don't trip
validators that do not apply.
*/}}
{{- define "pleme-lib.compliance.isWorkload" -}}
{{- $repo := (.Values.image | default dict).repository | default "" | toString -}}
{{- if ne $repo "" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Workload kind. Returns the lowercase kind string so validators can branch
on workload shape. Compounds: every future workload-shape-specific
validator (DaemonSet single-instance-per-node, Job parallelism, etc.)
reads this primitive.

  "deployment"   — default; replicas, rolling update, PDB, topology spread
  "statefulset"  — replicas, ordered, PVC per replica
  "cronjob"      — schedule-driven; no replicas; reliability via concurrencyPolicy
  "job"          — one-shot; no replicas
  "daemonset"    — per-node; no replicas; tolerates node taints
  "policy"       — pure-policy chart, no pod (e.g. pleme-compliance, NetworkPolicy-only chart)

Resolution: explicit .Values.compliance.workload.kind wins. Otherwise
auto-detect from values shape: if .Values.schedule is set → cronjob;
if .Values.image.repository is empty → policy; default → deployment.
*/}}
{{- define "pleme-lib.compliance.workloadKind" -}}
{{- $w := (.Values.compliance).workload | default dict -}}
{{- if $w.kind -}}
{{- $w.kind | toString | lower -}}
{{- else if .Values.schedule -}}
cronjob
{{- else if eq (include "pleme-lib.compliance.isWorkload" .) "false" -}}
policy
{{- else -}}
deployment
{{- end -}}
{{- end }}

{{/*
Validate. Called from _deployment.tpl before any resource is rendered.
Fails the template render with a clear error message if the selected
baseline's invariants would be violated.

This is the bedrock of "compliant primitives only": violation == no chart.
*/}}
{{- define "pleme-lib.compliance.validate" -}}
{{- $enforce := include "pleme-lib.compliance.enforce" . -}}
{{- if eq $enforce "true" -}}
{{- /*
     pleme-lib 0.9.0+: validation dispatches through the overlay registry.
     The resolved overlay list is computed via the back-compat shim from
     either explicit `.Values.compliance.overlays` or legacy
     `compliance.baseline / .airgap / .supplychain / .fips / .dod` values.
     Each registered overlay's `validate` template fires in order. See
     _overlay_dispatch.tpl for the dispatch primitive and
     docs/COMPLIANCE-OVERLAYS-DESIGN.md for the design.
*/ -}}
{{- include "pleme-lib.overlay.validateRegistry" . -}}
{{- include "pleme-lib.overlay.dispatchAll" (list "validate" .) -}}
{{- end -}}
{{- end }}
