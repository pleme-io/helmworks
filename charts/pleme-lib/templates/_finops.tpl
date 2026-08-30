{{/*
pleme-lib.finops — COST ATTRIBUTION, declared ONCE and projected to BOTH planes.

Ephemeral infrastructure is invisible in a bill unless every resource it creates
carries attribution AT CREATION. Two facts make that a hard deadline rather than
a nice-to-have:

  1. TAGS ARE NOT RETROACTIVE. A cost record is written with whatever tags the
     resource carried at the moment the meter ticked. Tagging afterwards fixes
     tomorrow's bill and nothing before it, so an environment that lived for six
     hours untagged is unattributable FOREVER — there is no backfill.
  2. A TAG KEY IS NOT A COST DIMENSION UNTIL IT IS ACTIVATED in the payer
     account. Until then every resource visibly carries the tag and the cost
     report has no column for it — the most convincing form of "we have
     attribution" that produces no attribution at all.

── THE FAILURE THIS TEMPLATE EXISTS TO PREVENT ──────────────────────────────
Attribution was emitted by TWO INDEPENDENT EMITTERS — one writing Kubernetes
labels on the workload, one writing cloud tags on the infrastructure — and
NEITHER carried cost. Attribution therefore broke at exactly the boundary where
real money is spent: the k8s plane knew who owned a pod, the cloud plane knew
who owned a volume, and no single key joined them. Two emitters is the defect.
So `finops.labels` and `finops.tags` here are not two emitters: they are two
PROJECTIONS of the one axis catalog below (`finops.axes`), both built by
ranging over it. Dropping an axis from one plane only is not a thing you can
express — you would have to delete it from the catalog, which drops it from
both, and the census (below) reports the new count so a test sees it.

── THE CASE LAW: LOWER-KEBAB, EVERYWHERE, KEYS AND VALUES ───────────────────
A live collision was measured: PascalCase keys on real resources, snake_case
in the taxonomy. CLOUD TAG KEYS ARE CASE-SENSITIVE, so `CostCentre` and
`cost_centre` are two different keys — and, per (2) above, activating one does
NOT activate the other. The estate then splits into a tagged half that shows up
in the report and a tagged half that does not, and both halves look correct
from the resource side. Kubernetes label keys are case-sensitive too, so a
selector written in the other case silently matches nothing.

That is why mixing case is a SILENT DEFECT and not a style question: neither
half errors, neither half looks wrong, and the only symptom is a cost report
whose total is smaller than the bill.

  ONE convention: lower-kebab — `^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$` — applied to
  BOTH key and value on BOTH planes, so a label value and its tag value are
  byte-identical and the join across the boundary is an equality.

Tier-honest about how the other case is excluded (do not round this up):
  - The five core axis KEY names are string literals in this file. There is no
    values key through which a caller could spell `CostCentre`.
      → TRULY UNREPRESENTABLE (no input surface exists).
  - `finops.extra`, `finops.labelPrefix` and `finops.tagPrefix` ARE caller
    supplied, and every axis VALUE is caller supplied. Those are refused by
    `fail` in `finops.guards`.
      → PARSE-TIME-REJECTED (an eval error), not unrepresentable.
We REFUSE rather than lower-case-and-continue on purpose: silently rewriting
`CostCentre` to `costcentre` invents a third key, and the caller's ledger — the
thing the cost report is reconciled against — still says `CostCentre`.

── THE FIVE AXES ────────────────────────────────────────────────────────────
  correlation-id — joins every resource of one instantiation across both planes
  feature        — branch / PR / ticket. The ONLY axis not derivable from the
                   others: one feature spawns many environments over time, so
                   rolling the correlation ids up does not reconstruct it, and
                   "what did this feature cost" is the question actually asked.
  cost-centre    — the budget the spend lands on; shape-checked against a
                   DECLARED pattern (default `^cc-[a-z0-9-]+$`, a generic
                   example — override `finops.costCentrePattern` for your own)
  requester      — the human or system that asked for it
  ephemeral      — plus `ttl-hours` when true. An ephemeral resource with no
                   stated ttl is the exact thing that runs until someone
                   notices the bill, so the pair is enforced in BOTH directions.

── DEFAULT OFF ─────────────────────────────────────────────────────────────
Absent `finops` renders nothing and refuses nothing: no existing consumer chart
changes behaviour by upgrading pleme-lib. But `enabled: false` WITH axes
declared is refused — that shape reads as "attribution is configured" and emits
none, and per (1) the resulting gap can never be repaired.

Entry points (all take the ROOT context `.`):
  pleme-lib.finops.guards — REFUSALS. Call it from every entry point, including
                            ones that compute without emitting.
  pleme-lib.finops.axes   — the catalog, as JSON. The single declaration.
  pleme-lib.finops.labels — k8s projection  (YAML map, `nindent` it)
  pleme-lib.finops.tags   — cloud projection (YAML map, `nindent` it)
  pleme-lib.finops.census — a MEASUREMENT of both rendered projections
*/}}

{{/*
pleme-lib.finops.shapePattern — the one case convention, in one place.

Deliberately the intersection of what all three planes accept: a Kubernetes
label value (≤63, alphanumeric ends, `-_.` inside), an AWS/Azure tag value, and
a GCP label (lowercase only). Anything outside it is rejected by SOMETHING
downstream, and which something depends on where the resource lands — an
admission rejection here, a silently-dropped label there.
*/}}
{{- define "pleme-lib.finops.shapePattern" -}}
^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$
{{- end }}

{{/*
pleme-lib.finops.costCentrePattern — the declared cost-centre shape.

A DECLARATION, not a hardcode: the default is a generic example and every
estate has its own scheme. What is not negotiable is that there IS a pattern —
a free-text cost centre is how `cc-platform`, `cc_platform` and `Platform`
become three budget lines that each look like the real one.
*/}}
{{- define "pleme-lib.finops.costCentrePattern" -}}
{{- $f := .Values.finops | default dict -}}
{{- $f.costCentrePattern | default "^cc-[a-z0-9-]+$" -}}
{{- end }}

{{/*
pleme-lib.finops.axes — THE SINGLE DECLARATION. Returns a JSON array of
  { axis, labelKey, tagKey, value }
one entry per ACTIVE axis, ordered. Both projections range over exactly this,
which is what makes plane drift unconstructible rather than merely tested.

Returns `[]` when finops is off, so both projections render empty and the
census reports 0 — a broken discovery path yields zero, never a plausible
smaller number.
*/}}
{{- define "pleme-lib.finops.axes" -}}
{{- $f := .Values.finops | default dict -}}
{{- $enabled := eq (toString ($f.enabled | default false)) "true" -}}
{{- $out := list -}}
{{- if $enabled -}}
  {{- $labelPrefix := $f.labelPrefix | default "finops.pleme.io" | toString -}}
  {{- $tagPrefix := $f.tagPrefix | default "finops-" | toString -}}
  {{- $pairs := list -}}
  {{- $pairs = append $pairs (dict "axis" "correlation-id" "value" ($f.correlationId | default "" | toString)) -}}
  {{- $pairs = append $pairs (dict "axis" "feature" "value" ($f.feature | default "" | toString)) -}}
  {{- $pairs = append $pairs (dict "axis" "cost-centre" "value" ($f.costCentre | default "" | toString)) -}}
  {{- $pairs = append $pairs (dict "axis" "requester" "value" ($f.requester | default "" | toString)) -}}
  {{- $ephemeral := eq (toString ($f.ephemeral | default false)) "true" -}}
  {{- $pairs = append $pairs (dict "axis" "ephemeral" "value" (ternary "true" "false" $ephemeral)) -}}
  {{- if $ephemeral -}}
    {{- $pairs = append $pairs (dict "axis" "ttl-hours" "value" ($f.ttlHours | default 0 | toString)) -}}
  {{- end -}}
  {{- /* Caller extensions ride the SAME catalog, so they reach both planes or
         neither. sortAlpha keeps the census and the golden literals stable. */ -}}
  {{- $extra := $f.extra | default dict -}}
  {{- range $k := (keys $extra | sortAlpha) -}}
    {{- $pairs = append $pairs (dict "axis" ($k | toString) "value" (index $extra $k | toString)) -}}
  {{- end -}}
  {{- range $p := $pairs -}}
    {{- $out = append $out (dict
          "axis" $p.axis
          "labelKey" (printf "%s/%s" $labelPrefix $p.axis)
          "tagKey" (printf "%s%s" $tagPrefix $p.axis)
          "value" $p.value) -}}
  {{- end -}}
{{- end -}}
{{- $out | toJson -}}
{{- end }}

{{/*
pleme-lib.finops.labels — the KUBERNETES projection of the catalog.
Renders a YAML map (or nothing when off). Splice with `nindent`.
*/}}
{{- define "pleme-lib.finops.labels" -}}
{{- $out := dict -}}
{{- range $a := (include "pleme-lib.finops.axes" . | fromJsonArray) -}}
{{- $_ := set $out $a.labelKey $a.value -}}
{{- end -}}
{{- if $out -}}
{{- toYaml $out -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.finops.tags — the CLOUD projection of the same catalog.
Same keys in the estate's own vocabulary, byte-identical values, so a k8s label
and a cloud tag join on equality with no normalisation step in between (a
normalisation step is where the two planes drift back apart).
*/}}
{{- define "pleme-lib.finops.tags" -}}
{{- $out := dict -}}
{{- range $a := (include "pleme-lib.finops.axes" . | fromJsonArray) -}}
{{- $_ := set $out $a.tagKey $a.value -}}
{{- end -}}
{{- if $out -}}
{{- toYaml $out -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.finops.census — the DENOMINATOR, measured from the RENDERED planes.

  axes=N labelKeys=N tagKeys=N paired=N

It re-parses what `labels` and `tags` actually emitted rather than counting the
catalog twice, so it is a measurement and not a restatement. `paired` counts
axes whose label value and tag value are both present and EQUAL — the property
the whole template exists to hold. Pin this string in a test beside the
field-by-field literals: a key dropped from one plane moves `labelKeys` or
`tagKeys` and `paired`, and a discovery path that breaks entirely reports 0.
*/}}
{{- define "pleme-lib.finops.census" -}}
{{- $axes := include "pleme-lib.finops.axes" . | fromJsonArray -}}
{{- $labels := include "pleme-lib.finops.labels" . | fromYaml -}}
{{- $tags := include "pleme-lib.finops.tags" . | fromYaml -}}
{{- $paired := 0 -}}
{{- range $a := $axes -}}
  {{- $lv := index $labels $a.labelKey | default "" | toString -}}
  {{- $tv := index $tags $a.tagKey | default "" | toString -}}
  {{- if and (ne $lv "") (eq $lv $tv) -}}
    {{- $paired = add1 $paired -}}
  {{- end -}}
{{- end -}}
{{- printf "axes=%d labelKeys=%d tagKeys=%d paired=%d" (len $axes) (len $labels) (len $tags) $paired -}}
{{- end }}

{{/*
pleme-lib.finops.guards — every refusal, in one block.

★ Call this from EVERY entry point, including ones that compute attribution
without emitting it (a lint, a dry run, an annotations-only caller). A guard
that lives inside the emit path is skipped by exactly the callers most likely
to report "attribution is configured" about a declaration that would be refused
at apply — the shape `pleme-lib.park` had to lift its two guards out of.

Each refusal names the values key at fault, because the caller's next action is
to edit that key.
*/}}
{{- define "pleme-lib.finops.guards" -}}
{{- $f := .Values.finops | default dict -}}
{{- $enabled := eq (toString ($f.enabled | default false)) "true" -}}
{{- $shape := include "pleme-lib.finops.shapePattern" . -}}

{{- if not $enabled -}}
  {{- /* DEFAULT OFF is silence, not a promise. But a block that declares axes
         and never emits them reads to its author as "attribution is on" — and
         because tags are not retroactive, the untagged window it opens can
         never be repaired. Refuse the contradiction instead of honouring the
         half of it that is cheaper. */ -}}
  {{- $declared := list -}}
  {{- range $k := (list "correlationId" "feature" "costCentre" "requester" "ttlHours" "extra") -}}
    {{- if index $f $k -}}{{- $declared = append $declared $k -}}{{- end -}}
  {{- end -}}
  {{- if eq (toString ($f.ephemeral | default false)) "true" -}}
    {{- $declared = append $declared "ephemeral" -}}
  {{- end -}}
  {{- if $declared -}}
    {{- fail (printf "pleme-lib.finops: finops.enabled is false but %v declared — a declared-and-unemitted axis reads as attribution and produces none, and cost records are not retroactively taggable. Set finops.enabled=true or remove the axes." $declared) -}}
  {{- end -}}
{{- else -}}

  {{- /* [1] Required axes. A resource missing any one of these is attributable
           to a narrower question than the one finance asks. */ -}}
  {{- if eq ($f.correlationId | default "" | toString) "" -}}
    {{- fail "pleme-lib.finops: finops.correlationId is required when finops.enabled=true — it is the only key that joins one instantiation's k8s objects to its cloud resources" -}}
  {{- end -}}
  {{- if eq ($f.feature | default "" | toString) "" -}}
    {{- fail "pleme-lib.finops: finops.feature is required when finops.enabled=true — branch/PR/ticket. It is NOT derivable from the other axes: one feature spawns many environments over time, so no rollup of correlation ids reconstructs it" -}}
  {{- end -}}
  {{- if eq ($f.costCentre | default "" | toString) "" -}}
    {{- fail "pleme-lib.finops: finops.costCentre is required when finops.enabled=true — without it the spend lands in the unattributed bucket, which is the bucket nobody owns" -}}
  {{- end -}}
  {{- if eq ($f.requester | default "" | toString) "" -}}
    {{- fail "pleme-lib.finops: finops.requester is required when finops.enabled=true — a cost with an owner gets cleaned up; a cost without one gets escalated" -}}
  {{- end -}}

  {{- /* [2] The cost centre matches a DECLARED pattern. */ -}}
  {{- $ccPattern := include "pleme-lib.finops.costCentrePattern" . -}}
  {{- $cc := $f.costCentre | toString -}}
  {{- if not (regexMatch $ccPattern $cc) -}}
    {{- fail (printf "pleme-lib.finops: finops.costCentre=%q does not match finops.costCentrePattern %q — a free-text cost centre becomes several budget lines that each look like the real one" $cc $ccPattern) -}}
  {{- end -}}

  {{- /* [3] ephemeral <-> ttl-hours, enforced in BOTH directions.
           true without a ttl is the resource that runs until the bill is
           noticed; a ttl without ephemeral is a durable resource carrying an
           expiry that some future reaper will believe. */ -}}
  {{- $ephemeral := eq (toString ($f.ephemeral | default false)) "true" -}}
  {{- $ttl := $f.ttlHours | default 0 | int -}}
  {{- if and $ephemeral (le $ttl 0) -}}
    {{- fail "pleme-lib.finops: finops.ephemeral=true requires finops.ttlHours > 0 — an ephemeral resource with no stated lifetime is a durable resource nobody has admitted to owning" -}}
  {{- end -}}
  {{- if and (not $ephemeral) (gt $ttl 0) -}}
    {{- fail (printf "pleme-lib.finops: finops.ttlHours=%d is set while finops.ephemeral is false — a durable resource advertising an expiry will eventually be believed by a reaper. Set finops.ephemeral=true or drop finops.ttlHours." $ttl) -}}
  {{- end -}}

  {{- /* [4] The case law, key side. The five core axis names are literals in
           this file and have no input surface; `extra` is the one place a
           caller names a key, so it is the one place the convention needs a
           refusal. A core-axis name reused here would `set` over the core
           projection with no error at all. */ -}}
  {{- $keyShape := "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" -}}
  {{- $core := list "correlation-id" "feature" "cost-centre" "requester" "ephemeral" "ttl-hours" -}}
  {{- range $k := (keys ($f.extra | default dict) | sortAlpha) -}}
    {{- if not (regexMatch $keyShape $k) -}}
      {{- fail (printf "pleme-lib.finops: finops.extra key %q is not lower-kebab (%s) — cloud tag keys are CASE-SENSITIVE, so a differently-cased key is a different cost dimension and is not activated by activating this one" $k $keyShape) -}}
    {{- end -}}
    {{- if has $k $core -}}
      {{- fail (printf "pleme-lib.finops: finops.extra key %q collides with core axis %q — it would overwrite the core projection silently. Set the core axis instead." $k $k) -}}
    {{- end -}}
  {{- end -}}

  {{- /* [5] The case law, value side, and the admission floor. Both planes
           carry the SAME bytes, so the value must satisfy the narrowest of the
           three consumers or the join stops being an equality. A >63-char
           value is rejected by the API server at admission, which fails the
           whole object — not just the label. */ -}}
  {{- range $a := (include "pleme-lib.finops.axes" . | fromJsonArray) -}}
    {{- $v := $a.value | toString -}}
    {{- if gt (len $v) 63 -}}
      {{- fail (printf "pleme-lib.finops: axis %q value is %d chars — a Kubernetes label value is capped at 63 and the API server rejects the whole object, not just the label" $a.axis (len $v)) -}}
    {{- end -}}
    {{- if not (regexMatch $shape $v) -}}
      {{- fail (printf "pleme-lib.finops: axis %q value %q is not lower-kebab (%s) — the k8s label and the cloud tag carry the same bytes so they join on equality; a value that only one plane accepts breaks the join where the money is" $a.axis $v $shape) -}}
    {{- end -}}
  {{- end -}}

  {{- /* [6] The two prefixes are caller-supplied, so they are the remaining
           way an uppercase key reaches either plane. */ -}}
  {{- $labelPrefix := $f.labelPrefix | default "finops.pleme.io" | toString -}}
  {{- $tagPrefix := $f.tagPrefix | default "finops-" | toString -}}
  {{- if not (regexMatch "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$" $labelPrefix) -}}
    {{- fail (printf "pleme-lib.finops: finops.labelPrefix=%q must be a lowercase DNS subdomain — a Kubernetes label key prefix is case-sensitive and a selector written in the other case matches nothing" $labelPrefix) -}}
  {{- end -}}
  {{- if not (regexMatch "^[a-z0-9][a-z0-9_-]*$" $tagPrefix) -}}
    {{- fail (printf "pleme-lib.finops: finops.tagPrefix=%q must be lowercase [a-z0-9_-] — cloud tag keys are case-sensitive and each case is a separate dimension that must be separately activated in the payer account" $tagPrefix) -}}
  {{- end -}}

{{- end -}}
{{- end }}
