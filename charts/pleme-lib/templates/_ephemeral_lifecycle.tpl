{{/*
pleme-lib.ephemeral — THE LIFECYCLE DECLARATION AN EPHEMERAL THING OWES.

An ephemeral thing is not ephemeral because someone called it that. It is
ephemeral when three facts are true of it AT CREATION, and all three have to be
stamped on the object itself, because every one of them is needed by something
that will run LATER, without the chart, without values, and without the person
who wrote them:

  (a) it declares its own EXPIRY, so a policy engine can age it out without
      being told anything else;
  (b) it is FINDABLE BY CORRELATION, so a reaper can enumerate one
      instantiation's whole footprint and prove that footprint is empty;
  (c) a reader for (b) is NAMED, because a correlation key nothing selects on
      is indistinguishable from no correlation key at all.

── THE THREE MEASURED FAILURES THIS EXISTS TO PREVENT ───────────────────────
Each one is a real incident shape, and none of them reported an error.

  1. A NAMESPACE DELETE BOUNDED ONLY BY NAMING DISCIPLINE. The call went out
     against an all-namespaces client with default delete parameters: no label
     selector, no ownerReference, no uid precondition, no never-delete list.
     Kubernetes answers 404 for a name that does not exist and the client
     treated 404 as success — so a WRONG NAME SUCCEEDS SILENTLY, and the only
     thing standing between a reaper and an unrelated namespace was that the
     string happened to be right. The render-time half of that bound is RBAC,
     and it lives in `pleme-lib.rbac` (see the namespace-delete guard added
     there, `pleme-lib.rbac.namespaceDeleteBound`). The declaration half is
     here: the correlation selector is the thing a delete can be scoped BY.

  2. A CORRELATION TAG WITH ZERO READERS. Objects were stamped, faithfully, for
     months. Nothing ever selected on the key. The tag looked like proof that a
     footprint could be enumerated, and no query existed that would have
     enumerated it — so "the environment was fully torn down" was never once
     checked, only assumed. `ephemeral.reapedBy` is required for exactly this:
     a chart cannot prove a reader RUNS, but it can refuse to stamp a
     correlation key that names no reader at all.

  3. A NAMESPACE-ABSENCE PROXY USED AS THE DONE SIGNAL. "The namespace is gone"
     fired roughly 120 seconds BEFORE the last managed resource actually was —
     namespace deletion is asynchronous, finalizers run after the object stops
     being listed, and cloud resources owned by controllers in that namespace
     outlive it entirely. Anything gated on that proxy (a cost stop-clock, a
     quota release, a "safe to reuse this name" decision) was gated on a signal
     that is early by construction. `ephemeral.doneSignal` names the arm and
     refuses that one, with the receipt, rather than leaving it a free string.

── WHAT THIS CHART CANNOT PROVE. READ THIS BEFORE CITING IT AS A GUARANTEE ──
A Helm chart runs once, at render, and then never again. It therefore CANNOT:

  * prove the reaper ran, or exists, or has credentials. `reapedBy` is a NAME.
    A name refuses the zero-reader shape; it does not establish a reader.
  * prove the clock advanced. `ttl-hours` is a bound a policy engine evaluates
    against each object's own `creationTimestamp`. Nothing here observes time.
  * prove a cloud resource is gone. The footprint that costs money is mostly
    NOT Kubernetes objects, and no selector in this file reaches it.
  * prove the footprint is empty. It emits the SELECTOR that makes the question
    answerable; answering it is a query somebody else has to run.

  It bounds the DECLARATION, never the call. Everything above is the operator's
  to verify at run time, and the honest claim for this template is exactly:
  "an ephemeral thing declared here is reapable-in-principle and enumerable."

── WHY THE EXPIRY IS RELATIVE AND NOT AN ABSOLUTE TIMESTAMP ─────────────────
The obvious shape is `lifecycle.pleme.io/expires-at: <RFC3339>`, computed with
`now`. It is wrong twice over. A reconciler re-renders continuously, so a
render-time `now` moves the expiry forward on every pass and the thing never
expires — the failure mode is invisible because each individual render looks
correct. And a render-time stamp is not a creation-time stamp: the gap between
them is a queue, a lock, or an approval, and it is unbounded. So the bound is
RELATIVE (`ttl-hours`) and is evaluated against the object's own
`creationTimestamp`, which the API server writes and nothing re-renders.

── ONE CATALOG, THREE PROJECTIONS ───────────────────────────────────────────
Same shape as `pleme-lib.finops`, and for the same reason: two independent
emitters of one fact drift, and the drift is silent on both sides. `axes` is
the single declaration; `labels` (what is STAMPED), `selector` (what is
MATCHED) and `match` (the whole policy triple) all range over it. A label that
is stamped but unselectable, or selected but unstamped, is not something you
can express — you would have to remove it from the catalog, which removes it
from all three, and `census` reports the new count so a test sees it.

  lifecycle.pleme.io/class           = "ephemeral"    SELECTABLE, literal
  lifecycle.pleme.io/correlation-id  = the footprint  SELECTABLE
  lifecycle.pleme.io/ttl-hours       = the age bound  NOT selectable

`ttl-hours` is deliberately not in the selector projection, and the reason is a
Kubernetes fact rather than a preference: a label selector has equality and
set-membership and NO numeric comparison, so `ttl-hours < elapsed` is not a
selector anyone can write. It is a policy PARAMETER, carried on the object so
the engine can read it per-object, and `match` emits it as `maxAgeHours`
alongside the selector rather than inside it. Putting it in `matchLabels` would
produce a policy that matches only the objects whose ttl is exactly that
number — which reads as a correct policy and reaps almost nothing.

── TIER-HONEST ABOUT WHAT IS ACTUALLY UNREPRESENTABLE ───────────────────────
  * The `class` value is the string literal `ephemeral` in this file. There is
    no values key through which a caller can spell it differently, so an
    object stamped `class: durable` while declaring itself ephemeral has no
    input surface. → TRULY UNREPRESENTABLE.
  * Every other refusal below is a `fail` on caller-supplied values.
    → PARSE-TIME-REJECTED (an eval error). Not the same tier; do not round up.
  * The three incident shapes above are prevented at DECLARATION only. The
    calls that caused them run elsewhere. → ONLY-MITIGATED, by construction.

── DEFAULT OFF ─────────────────────────────────────────────────────────────
Absent `ephemeral` renders nothing and refuses nothing: no existing consumer
chart changes behaviour by upgrading pleme-lib. But `enabled: false` with
lifecycle keys declared IS refused — that shape reads to its author as "this is
governed" and stamps nothing, which is the zero-reader failure (2) arriving
from the other direction.

── WHAT IS DELIBERATELY NOT HERE ────────────────────────────────────────────
  * COST attribution. `pleme-lib.finops` owns `correlation-id` and `ttl-hours`
    as cost axes and enforces `ephemeral <-> ttlHours` in both directions
    already. This template does not re-derive either number: when `finops` is
    declared it is the SOURCE, this reads from it, and a disagreement between
    the two is refused rather than resolved. One fact, one place. The two
    planes exist because a cost report and a reaper are different consumers of
    the same lifetime, not because the lifetime is two facts.
  * The label-VALUE shape. `pleme-lib.finops.shapePattern` already owns the one
    lower-kebab convention that a k8s label value, an AWS/Azure tag and a GCP
    label all accept; this includes it rather than writing a second regex, so
    a value that joins across planes for finops joins here too.
  * Wildcard RBAC bans, dedicated-SA requirements — `pleme-lib.compliance.*`.

Entry points (all take the ROOT context `.`; each calls the guards itself, so a
caller that computes without emitting cannot skip them — the skip is the shape
`pleme-lib.finops`'s own header warns about and `pleme-lib.park` had to fix):

  pleme-lib.ephemeral.resolved  the resolved lifetime, as JSON. No refusals.
  pleme-lib.ephemeral.guards    every refusal, in one block. Emits nothing.
  pleme-lib.ephemeral.axes      the catalog, as JSON. The single declaration.
  pleme-lib.ephemeral.labels    STAMP projection  (YAML map, `nindent` it)
  pleme-lib.ephemeral.selector  MATCH projection  (YAML map, `nindent` it)
  pleme-lib.ephemeral.match     the policy triple (kinds + selector + bound)
  pleme-lib.ephemeral.ttl       the bounded lifetime in hours, as a number
  pleme-lib.ephemeral.census    a MEASUREMENT of the rendered projections

VALUES

  ephemeral:
    enabled: true
    correlationId: ""          # defaults to finops.correlationId
    ttlHours: 0                # defaults to finops.ttlHours; must be a
                               # positive INTEGER, and <= maxTtlHours
    maxTtlHours: 168           # the declared ceiling (7d). A DECLARATION.
    kinds: []                  # what the policy matches. REQUIRED.
    reapedBy: ""               # the policy/controller that selects on these
                               # labels. REQUIRED. A name, not a proof.
    doneSignal: footprint-empty   # | namespace-absence  (REFUSED, see above)
*/}}

{{/*
pleme-lib.ephemeral.prefix — the one label-key namespace, in one place.
Not caller-supplied: a reaper's policy is written against a fixed key, and a
per-chart prefix is how one estate ends up with two selectors that each match
half of it. `finops` takes a prefix because a cost dimension is activated per
payer account; a lifecycle selector is not.
*/}}
{{- define "pleme-lib.ephemeral.prefix" -}}
lifecycle.pleme.io
{{- end }}

{{/*
pleme-lib.ephemeral.resolved — RESOLUTION ONLY, no refusals, as JSON.

Split out from the guards so that `guards` and `axes` read ONE resolution
rather than each re-deriving it — two resolvers is the same drift the catalog
below exists to prevent, one level up.

`ttlHours` and `correlationId` fall back to `finops` when this block does not
state them. `sourcedFrom` records which side won, and the census carries it, so
"where did this lifetime come from" is answerable from the rendered output
rather than by re-reading values.
*/}}
{{- define "pleme-lib.ephemeral.resolved" -}}
{{- $e := .Values.ephemeral | default dict -}}
{{- $f := .Values.finops | default dict -}}
{{- $enabled := eq (toString ($e.enabled | default false)) "true" -}}
{{- $corr := "" -}}
{{- $corrFrom := "none" -}}
{{- if ne ($e.correlationId | default "" | toString) "" -}}
  {{- $corr = $e.correlationId | toString -}}
  {{- $corrFrom = "ephemeral" -}}
{{- else if ne ($f.correlationId | default "" | toString) "" -}}
  {{- $corr = $f.correlationId | toString -}}
  {{- $corrFrom = "finops" -}}
{{- end -}}
{{- /* `hasKey`, not truthiness: 0 is falsy in Go templates, and a deliberate
       `ttlHours: 0` must reach the bound check as a declared zero rather than
       silently falling through to the finops value. Same shape the rbac
       pairing check had to learn about `namespaceEnvVars: []`. */ -}}
{{- $ttlRaw := "" -}}
{{- $ttlFrom := "none" -}}
{{- if hasKey $e "ttlHours" -}}
  {{- $ttlRaw = $e.ttlHours -}}
  {{- $ttlFrom = "ephemeral" -}}
{{- else if hasKey $f "ttlHours" -}}
  {{- $ttlRaw = $f.ttlHours -}}
  {{- $ttlFrom = "finops" -}}
{{- end -}}
{{- /* Same `hasKey` rule for the ceiling, and it is not hypothetical: written
       as `$e.maxTtlHours | default 168`, a deliberate `maxTtlHours: 0` — the
       spelling that REMOVES the ceiling — was rewritten to 168, the guard
       below never fired, and the suite's red run rendered green. Measured
       here, in this file, before it shipped. */ -}}
{{- $max := "168" -}}
{{- if hasKey $e "maxTtlHours" -}}
  {{- $max = $e.maxTtlHours | toString -}}
{{- end -}}
{{- dict
      "enabled" $enabled
      "correlationId" $corr
      "correlationFrom" $corrFrom
      "ttlRaw" ($ttlRaw | toString)
      "ttlFrom" $ttlFrom
      "maxTtlHours" $max
      "kinds" ($e.kinds | default list)
      "reapedBy" ($e.reapedBy | default "" | toString)
      "doneSignal" ($e.doneSignal | default "footprint-empty" | toString)
    | toJson -}}
{{- end }}

{{/*
pleme-lib.ephemeral.guards — every refusal, in one block. Emits nothing.

Each one names the values key at fault, because the caller's next action is to
edit that key.
*/}}
{{- define "pleme-lib.ephemeral.guards" -}}
{{- $e := .Values.ephemeral | default dict -}}
{{- $f := .Values.finops | default dict -}}
{{- $r := include "pleme-lib.ephemeral.resolved" . | fromJson -}}
{{- $shape := include "pleme-lib.finops.shapePattern" . -}}

{{- if not $r.enabled -}}
  {{- /* [0] DEFAULT OFF is silence. But a block that declares a lifetime and
         emits nothing reads as governed and is not — the objects go out
         unstamped, and once they exist there is no key to select them by.
         Refuse the contradiction instead of honouring the cheaper half. */ -}}
  {{- $declared := list -}}
  {{- range $k := (list "correlationId" "ttlHours" "kinds" "reapedBy" "doneSignal" "maxTtlHours") -}}
    {{- if hasKey $e $k -}}{{- $declared = append $declared $k -}}{{- end -}}
  {{- end -}}
  {{- if $declared -}}
    {{- fail (printf "pleme-lib.ephemeral: ephemeral.enabled is false but %v declared — a declared-and-unstamped lifecycle reads as governed and stamps nothing, and an object that goes out without the correlation key can never be found by the reaper afterwards. Set ephemeral.enabled=true or remove the keys." $declared) -}}
  {{- end -}}
{{- else -}}

  {{- /* [1] The footprint join key. Without it the reaper can enumerate
         nothing, and "the environment is gone" stays an assumption. */ -}}
  {{- if eq $r.correlationId "" -}}
    {{- fail "pleme-lib.ephemeral: ephemeral.correlationId is required when ephemeral.enabled=true (or set finops.correlationId and it is inherited) — it is the only key by which one instantiation's whole footprint can be enumerated, and a delete scoped by NAME instead answers 404-as-success when the name is wrong" -}}
  {{- end -}}
  {{- if gt (len $r.correlationId) 63 -}}
    {{- fail (printf "pleme-lib.ephemeral: ephemeral.correlationId is %d chars — a Kubernetes label value is capped at 63 and the API server rejects the WHOLE object, not just the label, so the thing goes out unstamped or not at all" (len $r.correlationId)) -}}
  {{- end -}}
  {{- if not (regexMatch $shape $r.correlationId) -}}
    {{- fail (printf "pleme-lib.ephemeral: ephemeral.correlationId=%q is not lower-kebab (%s) — this is pleme-lib.finops.shapePattern, shared on purpose: the same bytes are a k8s label here and a cloud tag there, and the two only join on equality" $r.correlationId $shape) -}}
  {{- end -}}
  {{- if and (ne ($e.correlationId | default "" | toString) "") (ne ($f.correlationId | default "" | toString) "") (ne ($e.correlationId | toString) ($f.correlationId | toString)) -}}
    {{- fail (printf "pleme-lib.ephemeral: ephemeral.correlationId=%q disagrees with finops.correlationId=%q. They are one fact — which instantiation this belongs to — and two spellings of it split the footprint: the reaper enumerates one half and the cost report attributes the other. Set one, or set both to the same value." ($e.correlationId | toString) ($f.correlationId | toString)) -}}
  {{- end -}}

  {{- /* [2] THE BOUND. An ephemeral thing that cannot expire is not
         ephemeral — that is the whole invariant, and every other field here
         is bookkeeping around it.

         A plain positive INTEGER is demanded rather than a list of
         unbounded-looking sentinels (`forever`, `-1`, `unlimited`, the shape
         `pleme-lib.pitr.snapshotPolicy` refuses by name). pitr needs the list
         because its bounds are optional and plural, so an absent field and a
         zero field must stay distinguishable. Here there is exactly one
         required field, so demanding that it BE a number is strictly stronger
         than enumerating the ways it might not be: it catches "forever",
         "1y", "∞" and every spelling nobody has thought of yet. */ -}}
  {{- if eq $r.ttlFrom "none" -}}
    {{- fail "pleme-lib.ephemeral: ephemeral.ttlHours is required when ephemeral.enabled=true (or set finops.ttlHours and it is inherited) — an ephemeral thing that cannot expire is a durable thing nobody has admitted to owning, and it is the one invariant this template exists for" -}}
  {{- end -}}
  {{- $ttlStr := $r.ttlRaw | toString -}}
  {{- if not (regexMatch "^-?[0-9]+$" $ttlStr) -}}
    {{- fail (printf "pleme-lib.ephemeral: %s.ttlHours=%q is not a whole number of hours. Anything that is not an integer is refused rather than cast, because every readable spelling of unbounded (\"forever\", \"never\", \"1y\") casts to 0 and 0 is indistinguishable from the field being absent — an unbounded lifetime would then render as a bounded-looking one." $r.ttlFrom $ttlStr) -}}
  {{- end -}}
  {{- $ttl := int $ttlStr -}}
  {{- if le $ttl 0 -}}
    {{- fail (printf "pleme-lib.ephemeral: %s.ttlHours=%d must be a positive number of hours. Zero and negative are not longer lifetimes; a policy engine reads both as no bound at all, and the object outlives everything that was ever going to look at it." $r.ttlFrom $ttl) -}}
  {{- end -}}
  {{- $maxStr := $r.maxTtlHours | toString -}}
  {{- if not (regexMatch "^-?[0-9]+$" $maxStr) -}}
    {{- fail (printf "pleme-lib.ephemeral: ephemeral.maxTtlHours=%q is not a whole number of hours. The ceiling is what makes 'bounded' bounded in BOTH directions; a ceiling that casts to 0 removes it." $maxStr) -}}
  {{- end -}}
  {{- $max := int $maxStr -}}
  {{- if le $max 0 -}}
    {{- fail (printf "pleme-lib.ephemeral: ephemeral.maxTtlHours=%d must be positive — a non-positive ceiling is not a wider one, it is the ceiling removed, and every ttl below then passes a check that is no longer checking." $max) -}}
  {{- end -}}
  {{- if gt $ttl $max -}}
    {{- fail (printf "pleme-lib.ephemeral: %s.ttlHours=%d exceeds ephemeral.maxTtlHours=%d. A lifetime long enough that nobody will still be watching is a durable resource wearing an expiry — it passes every audit that looks for 'is a ttl declared' and none that asks how long. Shorten the lifetime, or raise the ceiling deliberately and say why next to it." $r.ttlFrom $ttl $max) -}}
  {{- end -}}
  {{- if and (hasKey $e "ttlHours") (hasKey $f "ttlHours") (ne (int $e.ttlHours) (int $f.ttlHours)) -}}
    {{- fail (printf "pleme-lib.ephemeral: ephemeral.ttlHours=%d disagrees with finops.ttlHours=%d. One lifetime, two consumers — the reaper reads one number and the cost forecast reads the other, and the gap between them is billed to nobody. Set one, or set both to the same value." (int $e.ttlHours) (int $f.ttlHours)) -}}
  {{- end -}}

  {{- /* [3] finops declares the SAME lifetime under its own key, and its own
         guard already enforces ephemeral<->ttlHours in both directions. If
         finops is on and does NOT say ephemeral, the two planes describe
         different things about one object. */ -}}
  {{- if and (eq (toString ($f.enabled | default false)) "true") (ne (toString ($f.ephemeral | default false)) "true") -}}
    {{- fail "pleme-lib.ephemeral: ephemeral.enabled=true while finops.enabled=true and finops.ephemeral=false. The cost plane would attribute this as durable spend and the lifecycle plane would reap it — the same object, two lifetimes. Set finops.ephemeral=true." -}}
  {{- end -}}

  {{- /* [4] The reader. A correlation key nothing selects on is the measured
         zero-reader failure, and it is invisible: the objects carry the key,
         every review passes, and no query is ever written. A NAME is not a
         reader — see the CANNOT-PROVE section above — but a required name is
         the difference between an unanswered question and an unasked one. */ -}}
  {{- if eq $r.reapedBy "" -}}
    {{- fail "pleme-lib.ephemeral: ephemeral.reapedBy is required when ephemeral.enabled=true — name the policy or controller that SELECTS on these labels. A correlation key with no reader was stamped faithfully for months on one estate and never once queried, so 'the footprint is empty' was never checked. This is a name, not a proof: the chart cannot show the reaper runs." -}}
  {{- end -}}
  {{- if not (gt (len $r.kinds) 0) -}}
    {{- fail "pleme-lib.ephemeral: ephemeral.kinds is required when ephemeral.enabled=true — a lifecycle policy matches on (kind, selector, age bound), and an empty kind list is a policy that matches nothing while rendering as a complete one. List every kind this instantiation creates; a kind left out is a resource left behind." -}}
  {{- end -}}

  {{- /* [5] The done signal. Left as free text this defaults, in practice, to
         whichever proxy is cheapest to observe — and the cheapest one is
         wrong by about two minutes, always in the same direction. */ -}}
  {{- $signals := list "footprint-empty" "namespace-absence" -}}
  {{- if not (has $r.doneSignal $signals) -}}
    {{- fail (printf "pleme-lib.ephemeral: unknown ephemeral.doneSignal %q — one of %s" $r.doneSignal (join "|" $signals)) -}}
  {{- end -}}
  {{- if eq $r.doneSignal "namespace-absence" -}}
    {{- fail "pleme-lib.ephemeral: ephemeral.doneSignal=namespace-absence is refused. It is the arm people reach for and it fires EARLY — measured at roughly 120s before the last managed resource was actually gone. Namespace deletion is asynchronous: the object stops being listed while finalizers are still running, and any cloud resource a controller in that namespace owns outlives the namespace entirely. Anything gated on it (a cost stop-clock, a quota release, reusing the name) is gated on a signal that is early by construction. Use doneSignal=footprint-empty and query the correlation selector this template emits. The arm is kept declarable rather than deleted so the refusal carries its reason to whoever reaches for it." -}}
  {{- end -}}

{{- end -}}
{{- end }}

{{/*
pleme-lib.ephemeral.axes — THE SINGLE DECLARATION. A JSON array of
  { axis, key, value, selectable }
one entry per active axis, ordered. All three projections range over exactly
this, which is what makes stamp/selector drift unconstructible rather than
merely tested.

Returns `[]` when ephemeral is off, so every projection renders empty and the
census reports 0 — a broken discovery path yields zero, never a plausible
smaller number.
*/}}
{{- define "pleme-lib.ephemeral.axes" -}}
{{- include "pleme-lib.ephemeral.guards" . -}}
{{- $r := include "pleme-lib.ephemeral.resolved" . | fromJson -}}
{{- $p := include "pleme-lib.ephemeral.prefix" . -}}
{{- $out := list -}}
{{- if $r.enabled -}}
  {{- $pairs := list
        (dict "axis" "class" "value" "ephemeral" "selectable" true)
        (dict "axis" "correlation-id" "value" $r.correlationId "selectable" true)
        (dict "axis" "ttl-hours" "value" ((int $r.ttlRaw) | toString) "selectable" false) -}}
  {{- range $a := $pairs -}}
    {{- $out = append $out (dict
          "axis" $a.axis
          "key" (printf "%s/%s" $p $a.axis)
          "value" $a.value
          "selectable" $a.selectable) -}}
  {{- end -}}
{{- end -}}
{{- $out | toJson -}}
{{- end }}

{{/*
pleme-lib.ephemeral.labels — the STAMP projection. Every axis.
Renders a YAML map (or nothing when off). Splice with `nindent`.
*/}}
{{- define "pleme-lib.ephemeral.labels" -}}
{{- $out := dict -}}
{{- range $a := (include "pleme-lib.ephemeral.axes" . | fromJsonArray) -}}
{{- $_ := set $out $a.key $a.value -}}
{{- end -}}
{{- if $out -}}
{{- toYaml $out -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.ephemeral.selector — the MATCH projection. The selectable axes only.

This is the half that makes failure (2) unconstructible: it is not a second
hand-written list of keys that a reaper's policy is expected to agree with, it
is the same catalog filtered by one field. A key that reaches `labels` and not
this is not a thing you can express.
*/}}
{{- define "pleme-lib.ephemeral.selector" -}}
{{- $out := dict -}}
{{- range $a := (include "pleme-lib.ephemeral.axes" . | fromJsonArray) -}}
{{- if $a.selectable -}}
{{- $_ := set $out $a.key $a.value -}}
{{- end -}}
{{- end -}}
{{- if $out -}}
{{- toYaml $out -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.ephemeral.match — the whole triple a declarative lifecycle policy
engine needs: WHAT kinds, WHICH objects, and HOW OLD before it acts.

Emitted as a YAML fragment so a caller can splice it straight into whatever CR
its engine reads. The age bound rides OUTSIDE `matchLabels` on purpose — see
the header: a label selector has no numeric comparison, so a ttl inside
`matchLabels` yields a policy that matches only objects whose ttl is exactly
that number, which reads correct and reaps almost nothing.
*/}}
{{- define "pleme-lib.ephemeral.match" -}}
{{- $r := include "pleme-lib.ephemeral.resolved" . | fromJson -}}
{{- $sel := include "pleme-lib.ephemeral.selector" . | trim -}}
{{- if $sel -}}
reapedBy: {{ $r.reapedBy | quote }}
doneSignal: {{ $r.doneSignal | quote }}
kinds:
{{- range $k := $r.kinds }}
  - {{ $k | toString | quote }}
{{- end }}
maxAgeHours: {{ int $r.ttlRaw }}
selector:
  matchLabels:
    {{- $sel | nindent 4 }}
{{- end -}}
{{- end }}

{{/*
pleme-lib.ephemeral.ttl — the bounded lifetime, in whole hours.

Emits the number and nothing else, for splicing into a field. It is a resolved
and GUARDED value: reaching this template at all means the bound exists, is a
positive integer, is at or under the declared ceiling, and does not contradict
the cost plane. Renders empty when ephemeral is off.
*/}}
{{- define "pleme-lib.ephemeral.ttl" -}}
{{- include "pleme-lib.ephemeral.guards" . -}}
{{- $r := include "pleme-lib.ephemeral.resolved" . | fromJson -}}
{{- if $r.enabled -}}
{{- int $r.ttlRaw -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.ephemeral.census — the DENOMINATOR, measured from the RENDERED
projections.

  axes=N labels=N selector=N unstamped=N ttlSource=<s> corrSource=<s>

It re-parses what `labels` and `selector` actually emitted rather than counting
the catalog twice, so it is a measurement and not a restatement. `unstamped`
counts selectable axes that did NOT reach the stamp projection — the exact
zero-reader shape, and it is structurally 0 because both are projections of one
catalog, which is the point: the number is there so that a future edit which
breaks that property reports it. Pin this whole string in a test beside the
field-by-field literals: an axis dropped from either plane moves a count, and a
discovery path that breaks entirely reports 0 across the board and FAILS.
*/}}
{{- define "pleme-lib.ephemeral.census" -}}
{{- $axes := include "pleme-lib.ephemeral.axes" . | fromJsonArray -}}
{{- $labels := include "pleme-lib.ephemeral.labels" . | fromYaml -}}
{{- $sel := include "pleme-lib.ephemeral.selector" . | fromYaml -}}
{{- $r := include "pleme-lib.ephemeral.resolved" . | fromJson -}}
{{- $unstamped := 0 -}}
{{- range $a := $axes -}}
  {{- if $a.selectable -}}
    {{- $lv := index $labels $a.key | default "" | toString -}}
    {{- $sv := index $sel $a.key | default "" | toString -}}
    {{- if or (eq $lv "") (ne $lv $sv) -}}
      {{- $unstamped = add1 $unstamped -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- printf "axes=%d labels=%d selector=%d unstamped=%d ttlSource=%s corrSource=%s" (len $axes) (len $labels) (len $sel) $unstamped $r.ttlFrom $r.correlationFrom -}}
{{- end }}
