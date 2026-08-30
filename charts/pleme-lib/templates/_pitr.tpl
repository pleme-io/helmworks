{{/*
pleme-lib.pitr — the point-in-time-restore WINDOW, its retention policy, and
the key-material rule.

A restore target is only valid INSIDE A WINDOW WITH TWO BOUNDS, and almost
every implementation checks one of them. This template exists because the
missing half fails in the most expensive possible way: at the cloud API, at
restore time, with an error that reads like a permissions problem.

── THE WINDOW HAS TWO BOUNDS AND THEY HAVE OPPOSITE REMEDIES ────────────────
  earliest   the oldest restorable instant. Retention has aged everything
             before it out. A target BELOW this bound is not a wait — the
             data is GONE, and the only remaining path is a copy held
             somewhere the retention policy does not govern.
  latest     the newest restorable instant. It LAGS the wall clock, because
             the write-ahead log / change stream has not shipped yet. A
             target ABOVE this bound IS a wait: the bound advances on its
             own, and the restore that failed a minute ago succeeds later
             with no change to anything.

  ★ WHY BOTH BOUNDS ARE CHECKED HERE RATHER THAN AT THE ENGINE. The two
  failures are indistinguishable at the API — a target past `latest` and a
  target the caller has no grant for surface as the same class of refusal,
  and the operator reads "denied", goes looking for a policy, widens a
  grant, and retries into the same wall. Refusing at render time, NAMING THE
  BOUND, converts an hour of credential archaeology into one line.

  ★ `latest` IS NEVER DERIVED FROM now(). Rendering time is not observation
  time — a chart rendered in CI and applied twenty minutes later would carry
  a `latest` that was never measured against anything. Either declare the
  observed bound, or declare `observedAt` + `lagSeconds` and let this
  template subtract: both forms force the caller to have LOOKED.

── THE WINDOW CAN BE EMPTY, AND THAT IS A THIRD, DIFFERENT FAILURE ──────────
When retention is shorter than the shipping lag, `earliest` is at or after
`latest` and NO target is valid. Checking the target against each bound in
isolation reports whichever it crossed first and sends the operator to fix a
timestamp, when the real defect is a retention policy that cannot support
point-in-time restore at all.

── A RESTORE THAT CANNOT DECRYPT WHAT IT RESTORED MUST FAIL ─────────────────
The measured failure: a restored environment came up missing its key
material, MINTED A NEW KEY, and reported healthy. Every byte it had just
restored was now undecryptable, and nothing anywhere was red. The green was
the defect.

So the key-material source is a CLOSED SET with no minting arm — mint is not
a discouraged option here, it has no representation — and a restore that
declares it needs key material must say where that material comes from.
`generateIfMissing` is refused by name, because a self-healing restore is
indistinguishable from a working one until someone reads old ciphertext.

── AN EXPECTED SET WITHOUT A DENOMINATOR PROVES NOTHING ─────────────────────
A restore drill reported "3/3 absent" and passed while six objects it had
never heard of sat on the target: the expected set was hand-written, so the
drill could only ever check what someone remembered to list. Every count this
template emits is DERIVED from the structure it walked — `boundsChecked` is
the number of comparisons actually executed, not a literal `2`, so a bound
that stops being checked shows up as a smaller number rather than as silence.

── RETENTION WITH NO BOUND IS NOT RETENTION ─────────────────────────────────
Snapshots with no expiry accumulate forever; the bill is the only thing that
ever reports it, and it reports it late. `pitr.snapshot.retention` must
declare at least one real bound (`days` and/or `count`), and the sentinels
people reach for to mean "keep everything" — 0, -1, forever, unlimited,
never — are refused by name rather than silently read as a number.

── A HOUSEKEEPING RULE FOR THE fail() MESSAGES BELOW ────────────────────────
None of them contains a COLON FOLLOWED BY A SPACE in its prose. Measured on
helm-unittest v1.1.1 while building this template's suite — a `: ` inside the
message body left the render error unattributed to its template, so
`failedTemplate` reported "No failed document" and the assertion could not
pass no matter what pattern it carried. Removing the colon-space fixed it;
a colon with NO space (an instant like 12:00:00Z) is fine. Every prose colon
here is written as an em dash or a comma for that reason, and a new message
that reaches for one will quietly cost its own test.

Call convention — EVERY define takes ONE dict argument:
  (dict "root" $ "ctx" "<caller label woven into fail() messages>")

Usage in a consuming chart's templates/pitr.yaml:
  {{- include "pleme-lib.pitr.guards" (dict "root" $ "ctx" "my-chart") -}}
  {{- include "pleme-lib.pitr" (dict "root" $ "ctx" "my-chart") }}

Values — DEFAULT OFF, and every sub-leg independently off:
  pitr:
    enabled: false
    restore:
      enabled: false
      target: ""                # RFC3339 instant to restore to
      window:
        earliest: ""            # oldest restorable instant (retention floor)
        latest: ""              # newest restorable instant (ship-lag ceiling)
        observedAt: ""          # or: declare when you looked ...
        lagSeconds: 0           # ... and the lag you measured; latest is derived
      keyMaterial:
        required: false
        source: ""              # existingSecret|externalSecret|kmsKeyRef|hsmKeyRef
        ref: ""                 # the name/identifier at that source
    snapshot:
      enabled: false
      schedule: ""              # cron expression — required when enabled
      retention:
        days: 0                 # at least one of days/count must be a real bound
        count: 0
*/}}

{{/*
pleme-lib.pitr.epoch — parse one RFC3339 instant, or refuse.

Returns unix seconds. sprig's toDate yields the ZERO time on a parse failure
rather than erroring, and the zero time's epoch is large and negative — which
is how an unparseable instant would otherwise sail through every comparison
below as "very old" and turn the lower-bound guard into a coin flip. Instants
before 1970 are refused with it: a pre-epoch restore target is a typo.

  (dict "instant" "<rfc3339>" "field" "<values key>" "ctx" "<caller>")
*/}}
{{- define "pleme-lib.pitr.epoch" -}}
{{- $s := .instant | default "" | toString -}}
{{- $field := .field | default "instant" -}}
{{- $ctx := .ctx | default "pitr" -}}
{{- $e := toDate "2006-01-02T15:04:05Z07:00" $s | unixEpoch | atoi -}}
{{- if lt $e 0 -}}
{{- fail (printf "pleme-lib.pitr (%s): %s=%q is not an RFC3339 instant this template can compare (expected e.g. 2026-08-30T12:00:00Z). An unparseable instant does not error in a Go template — it becomes the zero time, which compares as older than every bound, so it would pass the earliest-bound check and be refused at the engine instead." $ctx $field $s) -}}
{{- end -}}
{{- $e -}}
{{- end }}

{{/*
pleme-lib.pitr.restoreWindow — validate the declared target against BOTH
bounds, and RETURN THE NUMBER OF BOUNDS COMPARED.

The return value is the denominator: it is the count of comparisons the loop
below actually executed, so dropping a bound from the table drops the number
a caller sees. A suite pinning it to 2 goes red when the upper bound quietly
stops being checked — which is the whole failure this template exists for, and
the one that leaves no other trace.

Returns "0" when restore is not enabled: absent is not a request, and a caller
asserting 2 on a disabled restore is asserting a check that never ran.
*/}}
{{- define "pleme-lib.pitr.restoreWindow" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "pitr" -}}
{{- $p := $root.Values.pitr | default dict -}}
{{- $r := $p.restore | default dict -}}
{{- if not $r.enabled -}}
0
{{- else -}}
{{- $target := $r.target | default "" | toString -}}
{{- if eq $target "" -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.target is required when pitr.restore.enabled is true — the RFC3339 instant to restore to. A restore with no declared target is a restore to whatever the engine picks, which is the newest thing it happens to hold; that is a decision, and it should be written down." $ctx) -}}
{{- end -}}
{{- $w := $r.window | default dict -}}

{{- /* ── the lower bound: retention's floor ─────────────────────────── */ -}}
{{- $earliest := $w.earliest | default "" | toString -}}
{{- if eq $earliest "" -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.window.earliest is required — the oldest restorable instant. Without it the only bound checked is the upper one, and a target that retention has already aged out renders clean and fails at the engine, where the error names neither the bound nor the retention policy that moved it." $ctx) -}}
{{- end -}}

{{- /* ── the upper bound: measured, or derived from a measured lag ───── */ -}}
{{- $latest := $w.latest | default "" | toString -}}
{{- $latestE := 0 -}}
{{- $latestSrc := "declared" -}}
{{- if ne $latest "" -}}
{{- $latestE = include "pleme-lib.pitr.epoch" (dict "instant" $latest "field" "pitr.restore.window.latest" "ctx" $ctx) | trim | atoi -}}
{{- else if $w.observedAt -}}
{{- $obsE := include "pleme-lib.pitr.epoch" (dict "instant" $w.observedAt "field" "pitr.restore.window.observedAt" "ctx" $ctx) | trim | atoi -}}
{{- $lag := int ($w.lagSeconds | default 0) -}}
{{- if le $lag 0 -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.window.observedAt is set without a positive pitr.restore.window.lagSeconds, so the derived upper bound would equal the observation instant. The upper bound LAGS the clock by construction — the log has not shipped yet — and a lag of zero is the assumption this template exists to refuse. Measure the lag and declare it, or declare pitr.restore.window.latest outright." $ctx) -}}
{{- end -}}
{{- $latestE = sub $obsE $lag | int -}}
{{- $latestSrc = "derived" -}}
{{- else -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.window.latest is required — the newest restorable instant, or pitr.restore.window.observedAt plus lagSeconds so it can be derived. It is deliberately NOT defaulted from now() — render time is not observation time, so a now()-shaped default would assert a bound nobody ever looked at, and would drift further from the truth the longer the rendered manifest sat before it was applied." $ctx) -}}
{{- end -}}

{{- $earliestE := include "pleme-lib.pitr.epoch" (dict "instant" $earliest "field" "pitr.restore.window.earliest" "ctx" $ctx) | trim | atoi -}}
{{- $targetE := include "pleme-lib.pitr.epoch" (dict "instant" $target "field" "pitr.restore.target" "ctx" $ctx) | trim | atoi -}}

{{- /* ── the window itself can be empty, and that is neither bound's fault */ -}}
{{- if ge $earliestE $latestE -}}
{{- fail (printf "pleme-lib.pitr (%s): the restore window is EMPTY — earliest=%q is at or after the %s upper bound. Retention is shorter than the shipping lag, so NO target is valid and moving pitr.restore.target cannot help. Checking the target against each bound alone would have reported whichever it crossed first and sent you to edit a timestamp; the defect is the retention policy. Lengthen retention past the lag, or shorten the lag." $ctx $earliest $latestSrc) -}}
{{- end -}}

{{- /* ── the two comparisons, and the denominator they produce ───────── */ -}}
{{- $bounds := list
      (dict "name" "earliest" "side" "below" "epoch" $earliestE "shown" $earliest)
      (dict "name" "latest"   "side" "above" "epoch" $latestE   "shown" (ternary $latest (printf "%s-%ds" ($w.observedAt | default "" | toString) (int ($w.lagSeconds | default 0))) (ne $latest ""))) -}}
{{- $checked := 0 -}}
{{- range $b := $bounds -}}
{{- if eq $b.side "below" -}}
{{- if lt $targetE (int $b.epoch) -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.target=%q is BELOW the window's earliest restorable instant %q. This is not a wait — retention has already aged that point out and the upper bound only ever moves forward, so no later attempt recovers it. The data exists only in a copy held outside this retention policy, if one was taken. Pick a target at or after %q, or restore from that copy." $ctx $target $b.shown $b.shown) -}}
{{- end -}}
{{- else -}}
{{- if gt $targetE (int $b.epoch) -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.target=%q is ABOVE the window's latest restorable instant %q, the %s upper bound. This one IS a wait — the log has not shipped that far yet and the bound advances on its own, so the same target succeeds later with nothing else changed. It is worth refusing here because the engine reports this as an access failure, the target it cannot reach and the target you are not permitted to reach surface identically, and the next move then looks like widening a grant, which never helps." $ctx $target $b.shown $latestSrc) -}}
{{- end -}}
{{- end -}}
{{- $checked = add1 $checked -}}
{{- end -}}
{{- $checked -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.pitr.keyMaterial — where the key comes from, or a refusal.

Returns the resolved source slug, or "none" when the restore does not declare
that it needs key material. The set is CLOSED and has NO minting arm: minting
is not a discouraged option here, it has no representation, because the failure
it produces is a restore that comes up GREEN having orphaned every prior
ciphertext. `generateIfMissing` / `mint` are additionally refused BY NAME, so a
caller who brings the habit from elsewhere gets told what it does rather than
an unknown-key shrug.
*/}}
{{- define "pleme-lib.pitr.keyMaterial" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "pitr" -}}
{{- $p := $root.Values.pitr | default dict -}}
{{- $r := $p.restore | default dict -}}
{{- $km := $r.keyMaterial | default dict -}}
{{- $sources := list "existingSecret" "externalSecret" "kmsKeyRef" "hsmKeyRef" -}}
{{- if or $km.generateIfMissing $km.mint -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.keyMaterial.generateIfMissing/mint is set. A restore that mints its own key when it cannot find one comes up healthy and reports nothing, while every byte it just restored is now undecryptable — the green is the defect, and it is discovered whenever somebody next reads old ciphertext. A restore that cannot decrypt what it restored must FAIL. Declare pitr.restore.keyMaterial.source (%s) with the ref to the key that encrypted this data." $ctx (join "|" $sources)) -}}
{{- end -}}
{{- if not $km.required -}}
none
{{- else -}}
{{- $src := $km.source | default "" | toString -}}
{{- if eq $src "" -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.keyMaterial.required is true but pitr.restore.keyMaterial.source is unset — a restore that needs key material must say WHERE that material comes from. Leaving it unset is exactly the state in which a restore silently mints a new key and reports success. Declare one of %s." $ctx (join "|" $sources)) -}}
{{- end -}}
{{- if not (has $src $sources) -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.keyMaterial.source=%q is not one of %s. The set is CLOSED on purpose and contains no minting arm — an unrecognised value is indistinguishable from a typo, and the value people reach for when the key is missing is the one that must not exist." $ctx $src (join "|" $sources)) -}}
{{- end -}}
{{- if not $km.ref -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.restore.keyMaterial.source=%q without pitr.restore.keyMaterial.ref — name the key at that source. A source with no ref resolves to whatever the engine's default is, which on a restored environment is usually a freshly created one." $ctx $src) -}}
{{- end -}}
{{- $src -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.pitr.snapshotPolicy — the retention/expiry declaration.

Returns the resolved policy as a YAML fragment, carrying its own DENOMINATOR
(`retentionBoundsDeclared`) so a policy that loses a bound reads as a smaller
number rather than as an unchanged-looking block.

Refuses unbounded retention. Snapshots with no expiry accumulate forever and
the bill is the only surface that ever reports it — late, and attributed to
storage rather than to the policy that was never written.
*/}}
{{- define "pleme-lib.pitr.snapshotPolicy" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "pitr" -}}
{{- $p := $root.Values.pitr | default dict -}}
{{- $s := $p.snapshot | default dict -}}
{{- if not $s.enabled -}}
enabled: false
retentionBoundsDeclared: 0
{{- else -}}
{{- $schedule := $s.schedule | default "" | toString -}}
{{- if eq $schedule "" -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.snapshot.enabled is true without pitr.snapshot.schedule. A snapshot policy with no schedule declares an intent nothing acts on, and the gap is invisible until a restore needs a snapshot that was never taken — at which point the window's earliest bound is simply later than anyone expected." $ctx) -}}
{{- end -}}
{{- $ret := $s.retention | default dict -}}
{{- if not $ret -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.snapshot.retention is unset — retention with no bound is not retention. Snapshots accumulate until somebody reads a bill, and by then the oldest ones have been paid for many times over. Declare pitr.snapshot.retention.days and/or pitr.snapshot.retention.count." $ctx) -}}
{{- end -}}
{{- $sentinels := list "0" "-1" "forever" "infinite" "unlimited" "never" "none" "keep" -}}
{{- $bounds := 0 -}}
{{- $days := 0 -}}
{{- $count := 0 -}}
{{- range $field := (list "days" "count") -}}
{{- $raw := (get $ret $field) -}}
{{- if not (kindIs "invalid" $raw) -}}
{{- $lit := $raw | toString | lower -}}
{{- if has $lit $sentinels -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.snapshot.retention.%s=%q reads as unbounded. The sentinels people reach for to mean keep-everything are refused by name rather than cast to a number, because %q casts to 0 and 0 is indistinguishable from the field being absent — an unbounded policy would then render as a bounded-looking one. Declare a real bound, or leave the field out and bound the other one." $ctx $field $lit $lit) -}}
{{- end -}}
{{- $n := int $raw -}}
{{- if lt $n 0 -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.snapshot.retention.%s=%d is negative. A negative bound is not a longer one; it is a typo that most engines read as no bound at all." $ctx $field $n) -}}
{{- end -}}
{{- if gt $n 0 -}}
{{- $bounds = add1 $bounds -}}
{{- if eq $field "days" -}}{{- $days = $n -}}{{- else -}}{{- $count = $n -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if eq $bounds 0 -}}
{{- fail (printf "pleme-lib.pitr (%s): pitr.snapshot.retention declares no real bound — at least one of pitr.snapshot.retention.days or .count must be a positive number. Both absent (or both zero) is unbounded retention wearing the shape of a policy — the block is present, review passes over it, and nothing ever expires." $ctx) -}}
{{- end -}}
enabled: true
schedule: {{ $schedule | quote }}
retentionDays: {{ $days }}
retentionCount: {{ $count }}
retentionBoundsDeclared: {{ $bounds }}
{{- end -}}
{{- end }}

{{/*
pleme-lib.pitr.guards — the ONE block every entry point calls.

Same lesson _park.tpl records: a guard reachable from only one of several
entry points is a guard that is sometimes not there. A chart that wants the
receipt, a lint that wants the verdict, and a caller that wants neither all
run these, and all of them run the SAME ones.
*/}}
{{- define "pleme-lib.pitr.guards" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "pitr" -}}
{{- $p := $root.Values.pitr | default dict -}}
{{- if $p.enabled -}}
{{- $_ := include "pleme-lib.pitr.restoreWindow" (dict "root" $root "ctx" $ctx) -}}
{{- $_ = include "pleme-lib.pitr.keyMaterial" (dict "root" $root "ctx" $ctx) -}}
{{- $_ = include "pleme-lib.pitr.snapshotPolicy" (dict "root" $root "ctx" $ctx) -}}
{{- end -}}
{{- end }}

{{/*
pleme-lib.pitr — the receipt.

Emits ONE ConfigMap recording the window that was validated, the bound count
that validated it, the key-material source, and the resolved retention policy.
It is a receipt, not a controller input: the point is that the numbers here are
DERIVED by the same code that did the checking, so a suite (or a human) reading
`boundsChecked: "2"` is reading the count of comparisons that actually ran.

Default off. Absent is not a request.
*/}}
{{- define "pleme-lib.pitr" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "pitr" -}}
{{- $p := $root.Values.pitr | default dict -}}
{{- if $p.enabled -}}
{{- $r := $p.restore | default dict -}}
{{- $w := $r.window | default dict -}}
{{- $checked := include "pleme-lib.pitr.restoreWindow" (dict "root" $root "ctx" $ctx) -}}
{{- $key := include "pleme-lib.pitr.keyMaterial" (dict "root" $root "ctx" $ctx) -}}
{{- $policy := include "pleme-lib.pitr.snapshotPolicy" (dict "root" $root "ctx" $ctx) -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "pleme-lib.fullname" $root }}-pitr
  labels:
    {{- include "pleme-lib.labels" $root | nindent 4 }}
data:
  restoreEnabled: {{ $r.enabled | default false | toString | quote }}
  restoreTarget: {{ $r.target | default "" | toString | quote }}
  windowEarliest: {{ $w.earliest | default "" | toString | quote }}
  windowLatest: {{ $w.latest | default "" | toString | quote }}
  windowObservedAt: {{ $w.observedAt | default "" | toString | quote }}
  windowLagSeconds: {{ $w.lagSeconds | default 0 | toString | quote }}
  boundsChecked: {{ $checked | trim | quote }}
  keyMaterialSource: {{ $key | trim | quote }}
  snapshotPolicy: |
    {{- $policy | nindent 4 }}
{{- end -}}
{{- end }}
