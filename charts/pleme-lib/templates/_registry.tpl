{{/*
pleme-lib: the CLOSED REGISTRY primitive — resolve a declared set of named
units against a known set, expand their dependencies, and refuse a name
nobody defined.

★ WHY THIS EXISTS, AND WHY IT IS NOT SPECULATIVE.

This was extracted on a CONVERGENCE, not on a duplication. Two systems in this
fleet arrived at the same resolution algorithm without coordinating:

  - `pleme-lib.overlay.list` (compliance overlays) — validate each declared
    name against a comma-separated registry, fail() on unknown, walk each
    overlay's `requires` to a fixpoint, dedupe preserving first-seen order.

  - `roteador.profile.*` (router profiles, helmworks-pleme) — validate each
    declared profile against `roteador.profiles.known`, refuse unknown, walk
    the resolved list in declaration order.

Duplication says a shape was convenient; convergence says it was FORCED by the
problem. Neither borrowed from the other — one governs FedRAMP controls, the
other governs UCI sections on a router — so the agreement is evidence the
algorithm is the problem's shape rather than one author's taste.

★ WHAT IS SHARED IS THE RESOLUTION, NOT THE SURFACE. The two systems emit
completely different things: overlays emit K8s object fragments, annotations
and NIST control IDs; router profiles emit a JSON list of UCI sections merged
per-option. Forcing those into one type would be a bad abstraction that looks
well-motivated. So this owns names only — a pure function from
(declared, registry) to an ordered, deduped, closed list — and every caller
keeps its own surfaces.

★ REFUSAL IS THE POINT. A typo'd name that resolved to nothing would render
exactly like a unit with no opinions: silently absent, indistinguishable from
correct. Both original implementations independently decided a wrong name must
be a build failure, which is the second thing the convergence attests.

USAGE

  {{- $names := include "pleme-lib.registry.resolve" (dict
        "declared"  .Values.compliance.overlays
        "registry"  (splitList "," (include "pleme-lib.overlay.registry" .))
        "requires"  "pleme-lib.overlay"
        "kind"      "compliance overlay"
        "ctx"       $) | fromYamlArray -}}

  declared  list   — what the consumer asked for. Empty list is legal and
                     resolves to empty; absence of intent is not an error.
  registry  list   — every name that exists. A name outside it is fatal.
  requires  string — template PREFIX for dependency expansion. The resolver
                     includes `<requires>.<name>.requires` and expects a
                     comma-separated list. OMIT IT ENTIRELY when a caller has
                     no dependency notion (router profiles do not) — passing
                     "" disables expansion rather than erroring, so a caller
                     never has to define empty `requires` templates just to
                     satisfy this.
  kind      string — what to call these in an error message. "overlay",
                     "router profile". Appears in the fail() text, so it is
                     the word the reader sees when they typo a name.
  ctx       $      — the root context, needed to `include` the requires
                     templates. There is no way to include without it.

Returns a YAML-serialized list; parse with `fromYamlArray`.
*/}}
{{- define "pleme-lib.registry.resolve" -}}
{{- $declared := .declared | default list -}}
{{- $registry := .registry | default list -}}
{{- $requires := .requires | default "" -}}
{{- $kind := .kind | default "unit" -}}
{{- $ctx := .ctx -}}
{{- if eq (len $registry) 0 -}}
  {{- fail (printf "pleme-lib.registry.resolve: empty registry for %s — a registry with no members can only ever refuse, which is never what a caller means" $kind) -}}
{{- end -}}
{{- /* ── Validate FIRST, before any expansion ──────────────────────────────
       Order is load-bearing: the requires-walk includes a template named
       after the unit, so an unknown name reaching it produces Go's raw
       "no template" error instead of a sentence naming the typo and the
       legal set. Validating up front is what makes the failure readable. */ -}}
{{- range $name := $declared -}}
  {{- if not (has $name $registry) -}}
    {{- fail (printf "unknown %s %q — not one of %v" $kind $name $registry) -}}
  {{- end -}}
{{- end -}}
{{- /* ── Closure expansion to a fixpoint ───────────────────────────────────
       Bounded at 10 because Go templates have no `while`, and a dependency
       chain deeper than ten is a misdeclaration rather than a design. The
       bound is not a correctness risk: reaching it means the fixpoint was
       never found, and the next validation pass catches whatever it pulled
       in. Expansion is SKIPPED entirely when no prefix was given. */ -}}
{{- if $requires -}}
  {{- range $i := until 10 -}}
    {{- $next := list -}}
    {{- range $name := $declared -}}
      {{- $req := include (printf "%s.%s.requires" $requires $name) $ctx | trim -}}
      {{- if $req -}}
        {{- range $r := splitList "," $req -}}
          {{- $rt := trim $r -}}
          {{- if and $rt (not (has $rt $next)) (not (has $rt $declared)) -}}
            {{- $next = append $next $rt -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
    {{- if gt (len $next) 0 -}}
      {{- /* A required name must exist too — a dependency on a unit nobody
             defined is the same defect as declaring one, and is MORE likely
             to go unnoticed because no human typed it at this call site. */ -}}
      {{- range $n := $next -}}
        {{- if not (has $n $registry) -}}
          {{- fail (printf "%s %q requires unknown %s %q — not one of %v" $kind (first $declared) $kind $n $registry) -}}
        {{- end -}}
      {{- end -}}
      {{- $declared = concat $next $declared -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- /* ── Dedupe, preserving FIRST-SEEN order ───────────────────────────────
       Order is a contract, not an implementation detail: callers layer these
       in sequence, so a resolver that returned a set would make the result
       depend on map iteration order — which Go deliberately randomises. */ -}}
{{- $resolved := list -}}
{{- range $n := $declared -}}
  {{- if not (has $n $resolved) -}}
    {{- $resolved = append $resolved $n -}}
  {{- end -}}
{{- end -}}
{{- $resolved | toYaml -}}
{{- end }}

{{/*
Dispatch: include one SURFACE of every resolved unit, in order.

A "surface" is a named template with a predictable suffix — the mechanism both
original systems used, e.g. `pleme-lib.overlay.fips.controls` or
`roteador.profile.repeater`. A unit that has nothing to say for a surface
defines an empty template rather than being special-cased here; that keeps the
dispatch a plain walk with no conditionals, which is the whole reason it can be
shared.

  {{- include "pleme-lib.registry.dispatch" (dict
        "names"   $resolved
        "prefix"  "pleme-lib.overlay"
        "surface" "controls"
        "ctx"     $) -}}

`surface` may be empty, in which case the template included is
`<prefix>.<name>` with no suffix — the shape router profiles use, where the
unit IS its single surface.
*/}}
{{- define "pleme-lib.registry.dispatch" -}}
{{- $prefix := .prefix -}}
{{- $surface := .surface | default "" -}}
{{- $ctx := .ctx -}}
{{- range $name := (.names | default list) -}}
{{- if $surface -}}
{{- include (printf "%s.%s.%s" $prefix $name $surface) $ctx -}}
{{- else -}}
{{- include (printf "%s.%s" $prefix $name) $ctx -}}
{{- end -}}
{{- end -}}
{{- end }}
