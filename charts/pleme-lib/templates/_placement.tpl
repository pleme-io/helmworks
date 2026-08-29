{{/*
pleme-lib.placement — the ISOLATION TRIPLE, emitted as ONE fragment.

A workload is isolated onto dedicated capacity by THREE facts that must all be
true at once, and each of the three is individually useless:

  1. the pod PINS to the pool          (nodeSelector — a label the pool stamps)
  2. the pod TOLERATES the pool's taint (tolerations — or it never schedules)
  3. the pool is TAINTED + scale-to-zero (so nothing else lands there and the
     capacity actually goes away when the workload does)

This template owns (1) and (2) — the pod half. (3) is the node-pool half and
lives wherever your pools are declared; see `pleme-lib.karpenterNodePool`. The
three are named together here because every failure below was a case of one of
them being present and looking correct while another was missing.

WHY THIS IS A TEMPLATE AND NOT THREE VALUES BLOCKS. Placement is where an
isolation decision either becomes real or silently evaporates, and every way it
evaporates renders clean, exits 0, and reports healthy. The guards below are the
whole point; the YAML is trivial.

────────────────────────────────────────────────────────────────────────────
THE FOUR RULES, AND THE RECEIPT BEHIND EACH
────────────────────────────────────────────────────────────────────────────

RULE 1 — THE PIN GOES PER-SUBCHART. NEVER THROUGH `global.*`.
  A `global.tolerations` reaches a subchart only if that subchart's own
  templates go looking for it. Measured on one production cluster over
  2026-07: an umbrella chart set the toleration globally, most subcharts
  honored it, several did not, and the divergence was invisible because a
  NoSchedule taint added to a running pool blocks NEW placements without
  evicting anything already there. Every existing pod stayed Running. The
  first pod created after that — one newly-enabled component — came up
  Pending/Unschedulable with "1 node(s) had untolerated taint(s)", and that
  was the first and only signal, weeks late. The root cause of the
  non-cascade turned out to be a stale vendored copy of the library chart
  winning Helm's flat, global named-template namespace, which is worse than
  a values bug: it is invisible to `helm template` on the chart you are
  reading.
  The rule that survives both diagnoses is the same one: set placement
  DIRECTLY, on the subchart that owns the pod. This template therefore never
  reads `.Values.global.*`, and refuses outright when a global placement key
  is the ONLY source (see the fail below) — because that is exactly the case
  where an author believes the global is doing the job.

RULE 2 — MATCH THE PROVISIONER LABEL WITH `Exists`, NEVER A POOL NAME.
  Requiring a node the autoscaler provisioned is a real requirement: nodes
  that boot from a managed node group's launch template do not receive the
  provisioner's node-class configuration, so a pod that lands on one fails
  later and elsewhere — at DNS, at a private registry pull, at a missing
  trust anchor — with an error that names none of this. Measured 2026-08:
  two workloads were stranded exactly that way, and a third was landing
  correctly by luck; a single reschedule was all it would have taken.
  But requiring the pool BY NAME is the wrong fix twice over. A named pool
  is usually the tainted one, so pinning to it while the toleration list
  says otherwise goes permanently unschedulable; and naming it couples the
  workload to one pool's identity, so the pool cannot be split, renamed or
  drained without editing every workload. `Exists` on the provisioner's
  nodepool label says the true requirement — "a node this autoscaler made" —
  against a label the non-provisioned nodes structurally lack. A new
  launch-template node is excluded with no edit here.
  This template gives that key `Exists` and NO values form. Trying to
  reintroduce a pool name through `provisioner.matchExpressions` is refused.

RULE 3 — `do-not-disrupt` FOR WORK THAT CANNOT BE CONSOLIDATED MID-FLIGHT.
  Two shapes need it, both observed live in 2026-08. A long, non-restartable
  build: the autoscaler's voluntary consolidation is perfectly entitled to
  reclaim its node, and the whole build is lost. And an always-on control
  singleton sharing a pool whose policy reclaims underutilized nodes: a
  process that is busy but cheap READS as underutilized, and the surrounding
  workloads get restarted with it.
  It is NOT an HA mechanism and must not be sold as one — involuntary
  reclamation of interruptible capacity is entirely unaffected by it. It
  suppresses the VOLUNTARY disruption only.

RULE 4 — NO DEFAULTS FOR `nodeSelector` OR `tolerations`. EVER.
  Helm does not merge list-valued values: a consumer who sets `tolerations`
  REPLACES the chart's default list wholesale. So a library default is worse
  than no default — it is present in every render where it was not needed
  and absent from exactly the render that overrode it, which is the render
  that was thinking about placement. The map-valued `nodeSelector` fails the
  other way: maps DO merge, so a library default label survives into a
  consumer's override and pins the pod to a pool that may not exist on their
  cluster.
  Both are therefore REQUIRED when placement is enabled, with no default,
  and the fail() names the key to set. Pool names, taint keys and label
  values are the consumer's to supply — this template ships the mechanism,
  never the membership.

────────────────────────────────────────────────────────────────────────────
WHAT THIS TEMPLATE DELIBERATELY DOES NOT CHECK
────────────────────────────────────────────────────────────────────────────
A taint key carried by EVERY pool is not an isolation boundary. If every
permanent service already tolerates it, those services colonize the
ephemeral pool and pin its nodes forever, and a pool that never empties
never scales to zero — the isolation reads as configured and the capacity
bill says otherwise. The isolating taint must be UNIQUE to the pool it
fences. A chart cannot see the other pools, so this is stated here as the
reason rather than enforced as a guard; the check belongs where the pools
are declared. Said plainly so the next author does not mistake the silence
for the rule not existing.

────────────────────────────────────────────────────────────────────────────
VALUES
────────────────────────────────────────────────────────────────────────────
  placement:
    enabled: true

    # REQUIRED when enabled — no default (RULE 4). The pool's own labels.
    nodeSelector:
      <label-key>: <label-value>

    # REQUIRED when enabled — no default (RULE 4). Must match the pool's
    # isolating taint. `operator: Equal` requires `value`; a keyless
    # toleration is refused (it tolerates EVERY taint, which is the opposite
    # of isolation).
    tolerations:
      - key: <pool-taint-key>
        operator: Equal
        value: "<pool-taint-value>"
        effect: NoSchedule

    provisioner:
      # Emit the "a node the autoscaler provisioned" nodeAffinity (RULE 2).
      requireProvisionedNode: false
      # The provisioner's own node-label key. A vendor API constant, not a
      # pool name — override only for a different provisioner.
      nodePoolLabelKey: karpenter.sh/nodepool
      # Extra REQUIRED expressions ANDed into the SAME term (os/arch pins).
      # Never the nodepool key — that is refused.
      matchExpressions: []

    # Raw escape hatch. Replaces the derived affinity entirely; setting it
    # together with requireProvisionedNode is refused rather than silently
    # resolved.
    affinity: {}

    # RULE 3. Suppresses VOLUNTARY consolidation only.
    doNotDisrupt: false
    disruptionAnnotationKey: karpenter.sh/do-not-disrupt

USAGE — two fragments, because they land in two different places:

  spec:
    template:
      metadata:
        annotations:
          {{- include "pleme-lib.placement.annotations" (dict "ctx" .) | nindent 10 }}
      spec:
        {{- include "pleme-lib.placement" (dict "ctx" .) | nindent 8 }}

A component with its own pool passes its own subtree, which is RULE 1 made
mechanical — each component names the placement it owns:

  {{- include "pleme-lib.placement" (dict "ctx" . "values" .Values.worker.placement) }}

NAMING. A future BREAKING change lands as `pleme-lib.placement.v2` beside
this one, never as a rewrite in place: Helm's named-template namespace is
flat and global, so once vendored copies exist an in-place change is
resolved by whichever copy parses last. A brand-new name is safe today
precisely because an older copy cannot define it — the include fails loudly
instead of rendering nothing.
*/}}

{{/*
The pod-SPEC half: nodeSelector + tolerations + affinity.
Arg: (dict "ctx" <root> ["values" <placement subtree>])
*/}}
{{- define "pleme-lib.placement" -}}
{{- $ctx := .ctx -}}
{{- if not $ctx -}}
{{- fail "pleme-lib.placement: call it as (dict \"ctx\" .) — the root context is required to read values; add \"values\" <subtree> to place one component of a multi-pod chart" -}}
{{- end -}}
{{- $p := .values | default $ctx.Values.placement | default dict -}}
{{- if $p.enabled -}}

{{- /* ── RULE 1: refuse the global smuggle ──────────────────────────────
     Checked BEFORE the missing-key fails, so an author who put the pin in
     `global` gets told where it actually belongs rather than being told to
     set a key they believe they already set. This template never READS
     `global.*`, so a global left in place is inert with respect to it —
     which is the silent miss, stated out loud. */ -}}
{{- $g := $ctx.Values.global | default dict -}}
{{- $globalPin := or (not (empty $g.placement)) (or (not (empty $g.nodeSelector)) (not (empty $g.tolerations))) -}}
{{- if and $globalPin (or (empty $p.nodeSelector) (empty $p.tolerations)) -}}
{{- fail "pleme-lib.placement: placement is declared under a `global.*` key but not on this subchart. A global reaches a subchart only if that subchart looks for it, and a NoSchedule taint added later blocks NEW pods without evicting the running ones — so the gap stays invisible until the next reschedule. Set placement.nodeSelector and placement.tolerations on THIS subchart (or pass its own subtree: include \"pleme-lib.placement\" (dict \"ctx\" . \"values\" .Values.<component>.placement))." -}}
{{- end -}}

{{- /* ── RULE 4: required, because a default would be discarded ────────── */ -}}
{{- if empty $p.nodeSelector -}}
{{- fail "pleme-lib.placement: placement.enabled=true requires placement.nodeSelector (a non-empty map of the pool's node labels). It takes NO default on purpose: Helm MERGES maps, so a library default label would survive into your override and pin this pod to a pool that may not exist on your cluster. Set placement.nodeSelector to the labels your node pool actually stamps." -}}
{{- end -}}
{{- if empty $p.tolerations -}}
{{- fail "pleme-lib.placement: placement.enabled=true requires placement.tolerations (a non-empty list matching the pool's isolating taint), or this pod pins to a tainted pool it cannot enter and sits Pending forever. It takes NO default on purpose: Helm REPLACES a list wholesale, so a library default would be dropped by exactly the consumer who overrode it. Set placement.tolerations." -}}
{{- end -}}

{{- /* ── each toleration must be able to MATCH ─────────────────────────
     Both shapes below render valid YAML, apply cleanly, and quietly fail to
     do what the author meant. `operator: Equal` (also the default when
     `operator` is omitted) with no `value` matches only the empty value, so
     a taint carrying `"true"` is not tolerated and the pod stays Pending
     while the manifest reads as if it were handled. A toleration with no
     `key` at all tolerates EVERY taint on the cluster, so the workload can
     land on any fenced pool — the exact opposite of the isolation this
     template exists to build, and the harder of the two to notice because
     the pod schedules and runs. */ -}}
{{- range $i, $t := $p.tolerations -}}
{{- $op := $t.operator | default "Equal" -}}
{{- if empty $t.key -}}
{{- fail (printf "pleme-lib.placement: placement.tolerations[%d] has no `key`, which tolerates EVERY taint in the cluster and lets this workload land on any fenced pool — the opposite of isolation. Name the pool's taint key." $i) -}}
{{- end -}}
{{- if and (eq $op "Equal") (kindIs "invalid" $t.value) -}}
{{- fail (printf "pleme-lib.placement: placement.tolerations[%d] (key %q) uses operator Equal — the default when `operator` is omitted — with no `value`, which matches only the EMPTY value and so does not tolerate a taint carrying one. Set placement.tolerations[%d].value to the taint's value, or use operator: Exists." $i $t.key $i) -}}
{{- end -}}
{{- end -}}

{{- $prov := $p.provisioner | default dict -}}
{{- $poolKey := $prov.nodePoolLabelKey | default "karpenter.sh/nodepool" -}}

{{- /* ── one field, one producer ─────────────────────────────────────── */ -}}
{{- if and (not (empty $p.affinity)) $prov.requireProvisionedNode -}}
{{- fail "pleme-lib.placement: placement.affinity and placement.provisioner.requireProvisionedNode both produce spec.affinity, and one would silently win. Fold the provisioner requirement into placement.affinity yourself, or drop placement.affinity and add your extra terms to placement.provisioner.matchExpressions." -}}
{{- end -}}

{{- /* ── RULE 2: the pool label is Exists-only, and stays that way ────── */ -}}
{{- range $i, $e := ($prov.matchExpressions | default list) -}}
{{- if eq ($e.key | default "") $poolKey -}}
{{- fail (printf "pleme-lib.placement: placement.provisioner.matchExpressions[%d] constrains %q, which this template already emits as `operator: Exists`. Naming a pool couples the workload to one pool's identity — it cannot be split, renamed or drained without editing every workload — and a named pool is usually the tainted one, so the pin fights the toleration and goes permanently unschedulable. Express what you actually need (arch, os, capacity type) as a different key, or supply a full placement.affinity and own the consequence." $i $poolKey) -}}
{{- end -}}
{{- end -}}

nodeSelector:
  {{- toYaml $p.nodeSelector | nindent 2 }}
tolerations:
  {{- toYaml $p.tolerations | nindent 2 }}
{{- if not (empty $p.affinity) }}
affinity:
  {{- toYaml $p.affinity | nindent 2 }}
{{- else if $prov.requireProvisionedNode }}
{{- /* ONE nodeSelectorTerm, deliberately. Terms are OR'd and the
       matchExpressions inside a term are AND'd — so splitting these across
       two terms turns "provisioned AND linux" into "provisioned OR linux",
       and the requirement evaporates while the YAML still looks like a
       constraint. Every extra expression joins THIS term. */ -}}
{{- $exprs := list (dict "key" $poolKey "operator" "Exists") -}}
{{- range ($prov.matchExpressions | default list) -}}
{{- $exprs = append $exprs . -}}
{{- end }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            {{- toYaml $exprs | nindent 12 }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
The pod-TEMPLATE-METADATA half: the disruption annotation (RULE 3).

Separate from the spec fragment because it lands in a different place in the
manifest, and separate rather than folded into a labels helper because it is
a placement decision, not an identity one. Emits nothing at all unless
`doNotDisrupt` is set, so it is safe to include unconditionally under an
`annotations:` key that already has other entries.

Arg: (dict "ctx" <root> ["values" <placement subtree>])
*/}}
{{- define "pleme-lib.placement.annotations" -}}
{{- $ctx := .ctx -}}
{{- if not $ctx -}}
{{- fail "pleme-lib.placement.annotations: call it as (dict \"ctx\" .) — the root context is required to read values" -}}
{{- end -}}
{{- $p := .values | default $ctx.Values.placement | default dict -}}
{{- if $p.doNotDisrupt -}}
{{ $p.disruptionAnnotationKey | default "karpenter.sh/do-not-disrupt" }}: "true"
{{- end -}}
{{- end -}}
