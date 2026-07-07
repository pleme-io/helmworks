{{/*
pleme-lib: compliance overlay registry — dispatch + closure + back-compat

The overlay registry is the canonical surface for compliance.

A workload declares:

  compliance:
    overlays:
      - fedramp-high
      - airgap-consumer
      - supplychain
      - fips
      - dod-il5

Each overlay name dispatches to a set of named templates with predictable
suffixes (the overlay's "surface"):

  pleme-lib.overlay.<name>.controls       — comma-separated NIST control IDs
  pleme-lib.overlay.<name>.requires       — comma-separated overlay names this requires
  pleme-lib.overlay.<name>.validate       — fail() invariants
  pleme-lib.overlay.<name>.annotations    — metadata annotation fragment
  pleme-lib.overlay.<name>.labels         — metadata label fragment
  pleme-lib.overlay.<name>.policies       — auto-rendered K8s objects (NetworkPolicy …)
  pleme-lib.overlay.<name>.manifestData   — compliance-manifest ConfigMap fragment
  pleme-lib.overlay.<name>.podEnv         — env list entries for Deployment containers
  pleme-lib.overlay.<name>.imagePullSecrets — pullsecret name list

If a surface is irrelevant, the overlay defines an empty template. The
dispatch unconditionally walks the resolved overlay list and includes
each surface — this is the entire dispatch logic.

The proof of compliance composes mechanically: applying overlays {O₁..Oₙ}
satisfies the union of {O₁.controls .. Oₙ.controls}. Adding HIPAA, PCI-DSS,
CMMC, NIS2, BSI C5, ISO 27001, … is one new `_overlay_<name>.tpl` file
plus one row in COMPLIANCE-PROOF.md.

See docs/COMPLIANCE-OVERLAYS-DESIGN.md for the full specification.
*/}}

{{/*
The list of overlay surfaces. The dispatcher walks each surface in order
when accumulating output across overlays. Adding a new surface (e.g.
podVolumes, podVolumeMounts, networkPolicyEgressRules, kyvernoPolicy)
means: define the surface in every overlay (empty if unused), add the
name here, and add a dispatch helper that uses it.
*/}}
{{- define "pleme-lib.overlay.surfaces" -}}
controls,requires,validate,annotations,labels,policies,manifestData,podEnv,imagePullSecrets,kyvernoPolicy,gatekeeperConstraint
{{- end }}

{{/*
The two admission-policy surfaces (kyvernoPolicy + gatekeeperConstraint)
make the proof symmetric: each overlay's chart-time validators are
mirrored by cluster-side admission policies emitted from the SAME overlay
declaration. A non-helmworks chart cannot bypass our invariants — Kyverno
or Gatekeeper rejects the pod at admission. Both sides come from one
declaration, so they cannot drift.

Charts that want to deploy these admission policies include:
  {{ include "pleme-lib.compliance.admissionPolicies" . }}
*/}}

{{/*
The full set of overlay names this registry knows about. Used for
synthesis (back-compat shim) and validation. The list is a single
string source-of-truth — when adding a new overlay, append its name
here and CI catches any orphaned overlay file.
*/}}
{{- define "pleme-lib.overlay.registry" -}}
fedramp-low,fedramp-moderate,fedramp-high,airgap-consumer,airgap-registry-mirror,mirror,supplychain,security-perderivation,fips,dod-il2,dod-il4,dod-il5,dod-il6,hipaa,cmmc-l3
{{- end }}

{{/*
Resolve the effective overlay list for this Release.

Resolution:
  1. If .Values.compliance.overlays is set, that list is the declared set.
  2. Otherwise, synthesize the list from legacy values (compliance.baseline,
     compliance.airgap.enabled, compliance.supplychain.enabled,
     compliance.fips.enabled, compliance.dod.impactLevel) for back-compat.
  3. Walk each declared overlay's `requires`; transitively expand. Bounded
     to 10 iterations (anything deeper than that is a misdeclaration).
  4. Deduplicate, preserving first-seen order.

Returns a YAML-serialized list (one overlay name per line, with `- `
prefix) that callers parse via `fromYamlArray`.
*/}}
{{- define "pleme-lib.overlay.list" -}}
{{- /* Use parens-default-dict to be safe when .Values.compliance is nil
       (chart consumers without a compliance section in values.yaml). */ -}}
{{- $declared := (.Values.compliance | default dict).overlays | default list -}}
{{- if eq (len $declared) 0 -}}
  {{- $declared = include "pleme-lib.overlay.synthesize" . | fromYamlArray -}}
{{- end -}}
{{- /* Validate every declared overlay name against the registry up
       front. Doing this here (rather than in a separate
       validateRegistry helper called only from compliance.validate)
       means any consumer of the list — annotations, controls, manifest,
       dispatch — gets a friendly fail() instead of the raw Go-template
       "no template" error when the requires-walk hits an unknown name. */ -}}
{{- $registry := splitList "," (include "pleme-lib.overlay.registry" .) -}}
{{- range $name := $declared -}}
  {{- if not (has $name $registry) -}}
    {{- fail (printf "compliance: unknown overlay %q (not in pleme-lib.overlay.registry: %v)" $name $registry) -}}
  {{- end -}}
{{- end -}}
{{- /* Closure expansion: walk requires until fixpoint */ -}}
{{- $resolved := list -}}
{{- range $i := until 10 -}}
  {{- $next := list -}}
  {{- range $name := $declared -}}
    {{- $req := include (printf "pleme-lib.overlay.%s.requires" $name) $ | trim -}}
    {{- if $req -}}
      {{- range $r := splitList "," $req -}}
        {{- $rt := trim $r -}}
        {{- if and $rt (not (has $rt $next)) (not (has $rt $declared)) -}}
          {{- $next = append $next $rt -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if eq (len $next) 0 -}}
    {{- /* fixpoint reached */ -}}
  {{- else -}}
    {{- $declared = concat $next $declared -}}
  {{- end -}}
{{- end -}}
{{- /* Dedup, preserve first-seen order */ -}}
{{- range $n := $declared -}}
  {{- if not (has $n $resolved) -}}
    {{- $resolved = append $resolved $n -}}
  {{- end -}}
{{- end -}}
{{- $resolved | toYaml -}}
{{- end }}

{{/*
Synthesize an overlay list from the legacy values surface.
This is the back-compat shim — existing charts using
`compliance.baseline=fedramp-high`, `compliance.airgap.enabled=true`,
etc. continue to work without touching values; the synthesis maps them
into the equivalent overlay declaration.
*/}}
{{- define "pleme-lib.overlay.synthesize" -}}
{{- /* Read raw values directly (NOT via the higher-level
       compliance.baseline / dod.impactLevel helpers) to break a
       potential recursion: those helpers themselves call
       pleme-lib.overlay.list which would cycle back here. */ -}}
{{- $list := list -}}
{{- $b := ((.Values.compliance | default dict).baseline | default "") | toString | lower | trim -}}
{{- if eq $b "fedramp-low" -}}{{- $list = append $list "fedramp-low" -}}{{- end -}}
{{- if eq $b "fedramp-moderate" -}}{{- $list = append $list "fedramp-moderate" -}}{{- end -}}
{{- if eq $b "fedramp-high" -}}{{- $list = append $list "fedramp-high" -}}{{- end -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- if eq (toString $ag.enabled) "true" -}}
  {{- $role := $ag.role | default "consumer" | toString -}}
  {{- if eq $role "consumer" -}}{{- $list = append $list "airgap-consumer" -}}{{- end -}}
  {{- if eq $role "registry-mirror" -}}{{- $list = append $list "airgap-registry-mirror" -}}{{- end -}}
{{- end -}}
{{- $sc := (.Values.compliance).supplychain | default dict -}}
{{- if eq (toString $sc.enabled) "true" -}}{{- $list = append $list "supplychain" -}}{{- end -}}
{{- /* security.perDerivation.enabled synthesizes the umbrella overlay,
       which `requires` supplychain (pulled in by the closure walk). */ -}}
{{- $pd := (.Values.security | default dict).perDerivation | default dict -}}
{{- if eq (toString $pd.enabled) "true" -}}{{- $list = append $list "security-perderivation" -}}{{- end -}}
{{- $m := (.Values.compliance).mirror | default dict -}}
{{- if and $m.upstreams (gt (len ($m.upstreams | default list)) 0) -}}
  {{- if not (has "airgap-registry-mirror" $list) -}}
    {{- $list = append $list "mirror" -}}
  {{- end -}}
{{- end -}}
{{- $f := (.Values.compliance).fips | default dict -}}
{{- if eq (toString $f.enabled) "true" -}}{{- $list = append $list "fips" -}}{{- end -}}
{{- $d := (.Values.compliance).dod | default dict -}}
{{- $il := $d.impactLevel | default "" | toString | lower | trim -}}
{{- if $il -}}{{- $list = append $list (printf "dod-%s" $il) -}}{{- end -}}
{{- $list | toYaml -}}
{{- end }}

{{/*
Apply a surface across all resolved overlays and concatenate output.
Usage: include "pleme-lib.overlay.dispatchAll" (list "validate" .)
*/}}
{{- define "pleme-lib.overlay.dispatchAll" -}}
{{- $surface := index . 0 -}}
{{- $ctx := index . 1 -}}
{{- $list := include "pleme-lib.overlay.list" $ctx | fromYamlArray -}}
{{- range $name := $list -}}
{{- $body := include (printf "pleme-lib.overlay.%s.%s" $name $surface) $ctx -}}
{{- if (trim $body) }}
{{ $body | trim }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Apply a surface across all resolved overlays, separating each non-empty
contribution with `---` (a YAML document separator). Used for surfaces
that emit multi-document manifests (kyvernoPolicy, gatekeeperConstraint,
policies) where each overlay's contribution is a complete K8s YAML
document.

Usage: include "pleme-lib.overlay.dispatchDocuments" (list "kyvernoPolicy" .)
*/}}
{{- define "pleme-lib.overlay.dispatchDocuments" -}}
{{- $surface := index . 0 -}}
{{- $ctx := index . 1 -}}
{{- $list := include "pleme-lib.overlay.list" $ctx | fromYamlArray -}}
{{- $first := true -}}
{{- range $name := $list -}}
{{- $body := include (printf "pleme-lib.overlay.%s.%s" $name $surface) $ctx | trim -}}
{{- if $body -}}
{{- if $first -}}{{- $first = false -}}{{- else }}
---
{{ end -}}
{{ $body }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Apply a surface across all overlays, joining with a separator. Used for
controls (CSV) — each overlay returns a control string; the dispatcher
concatenates with comma separators.
*/}}
{{- define "pleme-lib.overlay.dispatchJoin" -}}
{{- $surface := index . 0 -}}
{{- $ctx := index . 1 -}}
{{- $sep := index . 2 -}}
{{- $list := include "pleme-lib.overlay.list" $ctx | fromYamlArray -}}
{{- $accum := list -}}
{{- range $name := $list -}}
  {{- $val := include (printf "pleme-lib.overlay.%s.%s" $name $surface) $ctx | trim -}}
  {{- if $val -}}{{- $accum = append $accum $val -}}{{- end -}}
{{- end -}}
{{- join $sep $accum -}}
{{- end }}

{{/*
Validate the resolved overlay list itself — every name must be in
the registry; any unknown name fails with a clear error.
*/}}
{{- define "pleme-lib.overlay.validateRegistry" -}}
{{- $registry := splitList "," (include "pleme-lib.overlay.registry" .) -}}
{{- $list := include "pleme-lib.overlay.list" . | fromYamlArray -}}
{{- range $name := $list -}}
  {{- if not (has $name $registry) -}}
    {{- fail (printf "compliance: unknown overlay %q (not in pleme-lib.overlay.registry: %v)" $name $registry) -}}
  {{- end -}}
{{- end -}}
{{- end }}
