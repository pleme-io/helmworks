{{/*
pleme-lib.park — the PARK / UNPARK verb table.

Park floors a workload to ZERO COST without deleting it: the declaration stays
the source of truth, only the running pods go away, and unpark is a revert of
one field rather than a re-derivation from memory. This is MODULARIZE, DON'T
DELETE at the runtime layer.

★ WHAT THIS SHIPS, AND WHAT IT DELIBERATELY DOES NOT.
It ships the VERBS, the DISPATCH between them, the PRECEDENCE, and the GUARDS.
It ships NO MEMBERSHIP. Which components sit on which rung is a dependency
ordering of one specific cluster — an architecture diagram that survives
renaming every literal in it — so the caller supplies `park.rung` per component
and `park.consumerRungs` for the things that read it, and this library never
learns who anything is. Same rule pleme-lib.routing states for destinations:
the reusable artifact is the RULE and the ARMS, never the catalog.

── WHY PARK IS SAFE AT ALL ──────────────────────────────────────────────────
Scale-to-zero is NOT eviction. A PodDisruptionBudget gates the Eviction API
(`pods/eviction`) only; taking a Deployment or StatefulSet to zero deletes its
pods through the controller, so a PDB sitting at ALLOWED DISRUPTIONS = 0 never
enters the picture. The obvious park — delete the nodes — hits those PDBs,
deadlocks, and gets "resolved" with a force drain that SIGKILLs a database at
the grace period. Removing the PODS and letting the node autoscaler reap the
emptied nodes on its own consolidation path costs the same and kills nothing.
Every verb below removes pods or ceilings. None of them removes an OBJECT.

── PRECEDENCE IS FIXED: park > scaleToZero > breathe ────────────────────────
A parked workload must not be un-parked by an autoscaler. An operator-asserted
floor outranks an activation policy (0<->1), which outranks a proportional
resource band (N<->M). This template REFUSES to render a park that an
autoscaler owning the same replica field would lift on its next tick — see
the precedence guard. The only verb that survives a live autoscaler is
`pausedReplicas`, which pins the target regardless of what any trigger reports.

  ★ A never-occurring trigger WINDOW IS NOT A PARK. A cron-style scaler derives
  its window from next-start vs next-end, so an impossible date reports ACTIVE
  rather than "outside" and the target stays at whatever count it already had.
  Measured on one production cluster, 2026-08: eight services held at one
  replica each through a clean apply, with the scaler Ready and every status
  green. Pin with the paused-replicas annotation or do not claim a park.

── THE VERB TABLE ───────────────────────────────────────────────────────────
Every verb is an UPSTREAM API surface. Nothing here is a pleme-io invention.

  replicas            spec.replicas: 0 on a Deployment / StatefulSet / ReplicaSet
  chartReplicas       a chart value that renders that field, patched to 0
  postRenderer        a Flux postRenderers kustomize patch on the RENDERED object
  pausedReplicas      the KEDA paused-replicas annotation on the ScaledObject
  hpaFloor            spec.minReplicas on a HorizontalPodAutoscaler
  jobSuspend          spec.suspend: true on a Job / CronJob
  fluxSuspend         spec.suspend: true on a reconciled DECLARATION
  scaleSubresource    spec.replicas on a CR that serves /scale
  nodeSelectorSink    an unsatisfiable nodeSelector — a DaemonSet's replicas 0
  provisionerCeiling  a node-provisioner `limits` block — a CEILING, not an evictor

── THE DISPATCH ─────────────────────────────────────────────────────────────
Inputs: (objectKind, ownerKind, zeroSafe, operatorReconciles, intent). First
match wins. Each arm carries the receipt that forced it.

  intent = declaration
    Job|CronJob                     -> jobSuspend
    HelmRelease|Kustomization       -> fluxSuspend
    ★ fluxSuspend STOPS RECONCILIATION, NOT PODS. The workload keeps running
      and keeps billing. Under intent=cost this verb is unreachable on purpose.

  intent = cost
    ownerKind = autoscaler          -> pausedReplicas | hpaFloor
    DaemonSet                       -> nodeSelectorSink
    Job|CronJob                     -> jobSuspend
    NodePool                        -> provisionerCeiling
    operatorReconciles + helm       -> chartReplicas   (the CR's value, never the
                                       rendered object — a postRenderer on the
                                       object an operator owns is REVERTED on
                                       its next reconcile)
    operatorReconciles              -> scaleSubresource
    HelmRelease + zeroSafe          -> chartReplicas
    HelmRelease + !zeroSafe         -> postRenderer
    CustomResource                  -> scaleSubresource
    Deployment|StatefulSet|ReplicaSet -> replicas

  ★ zeroSafe IS A MEASUREMENT, NOT AN ASSUMPTION. Go templates treat integer 0
  as empty, so a chart writing `replicas: {{ .Values.replicaCount | default 1 }}`
  accepts 0, renders 1, and reports a successful upgrade. Some charts also ship
  a values schema with `minimum: 1`, which aborts the whole upgrade instead.
  Both were found on one production cluster, 2026-08, in charts that had looked
  parkable for months. Set zeroSafe only after rendering the chart with 0 and
  reading the output.

── THE EXEMPTION PREDICATE ──────────────────────────────────────────────────
Some components must never be parked, and parking them is worse than not
parking at all — it looks applied and either does nothing or seals the cluster
shut. Declaring any predicate true REFUSES the render.

  admitsOwnUnpark     it serves a Fail-policy admission webhook that must admit
                      the very update that LIFTS the park (lifting a hibernation
                      annotation is an UPDATE), or that gates an object the
                      reconciler re-applies every pass. With no endpoints the
                      webhook rejects, the whole reconciliation goes NotReady,
                      and nothing in git can reopen it.
  carriesOutThePark   it is the controller whose reconcile TURNS this park's
                      declaration into floored pods. Parking it in the same
                      commit is a race the park loses every time: the release
                      controller waits on a status the parked operator can no
                      longer advance, times out, and remediation rolls the park
                      back to its pre-park replica count.
  universalDependency every workload depends on it by construction — the
                      in-cluster registry, DNS, CNI, the CSI driver. NO rung is
                      high enough: any reschedule, node roll or restart during
                      the park then fails. Measured on one production cluster,
                      2026-08: an in-cluster registry parked below its readers
                      left pods in ImagePullBackOff for hours against a service
                      with nothing listening, saving one small pod's requests
                      while the only recurring charge (its volume) billed anyway.
  recoveryPathOnly    it IS the unpark path — the reconciler, the node
                      provisioner, the certificate issuer, the secret syncer.
                      Flooring it converts recovery from a git revert into an
                      out-of-band change.
  pinnedToParkedCapacity  it is pinned (nodeSelector / affinity / architecture)
                      to capacity this park removes, so it would sit Pending
                      forever. That is an unfinished park, not a steady state.

── TWO TRAPS IN THE PATCH LAYER ─────────────────────────────────────────────
1. A JSON-patch `add` at an ARRAY'S OWN PATH REPLACES the array; it does not
   append. `add /spec/postRenderers` with a list value silently discards
   whatever the target already had there — which on one production cluster was
   the patch injecting a priorityClassName. Appending needs the `/-` form. This
   template cannot see the live object, so `park.target.existingPostRenderers`
   is REQUIRED for the postRenderer verb: defaulting it would make the
   destructive branch the silent one.
2. TWO PATCHES ON THE SAME PATH IS A CONFLICT. Two park components that both
   `add /spec/postRenderers` to the same release collide on apply. The dispatch
   below refuses to render two targets that resolve to the same
   (kind, namespace, name, path) — the collision is caught at template time
   rather than at apply time.

── THE HELM REMEDIATION DISARM, EMITTED AUTOMATICALLY ───────────────────────
A release-mediated park (chartReplicas / postRenderer) also disables hooks and
remediation for the duration. A post-upgrade hook that waits for the stack to
come up healthy is precisely what a park prevents: the upgrade times out, the
release is marked failed, remediation ROLLS IT BACK, and every workload returns
to its pre-park replica count and then crash-loops against datastores that are
on their way down. Measured on one production cluster, 2026-08: the park
applied correctly and was undone by its own rollback within the same reconcile.

── ORDERING ─────────────────────────────────────────────────────────────────
Park descends by ASCENDING rung; unpark ascends by DESCENDING rung. A reader
parks at or before what it reads, so a partial unpark can never strand a
service against a missing datastore, and a partial park can never strand a
running reader against a floored dependency. Nothing checks that edge unless
you declare it: `park.consumerRungs` is the caller's list of rungs that READ
this component, and a reader at a HIGHER rung is refused.

  ★ Rung membership follows the DEPENDENCY GRAPH, not a word. A service and the
  datastores it reads park and unpark as ONE unit. Measured on one production
  cluster, 2026-08: a build cache and its two backends were split across two
  rungs, and a partial unpark left the backends Running with an attached volume,
  billing, backing a server that was still floored — visible only as a cold
  build with zero paths substituted.

Call convention — EVERY define takes ONE dict argument:
  (dict "root" $ "ctx" "<caller label woven into fail() messages>")
  pleme-lib.park.verb additionally takes an explicit target:
  (dict "target" <dict> "intent" <string> "ctx" <string>)

Values:
  park:
    enabled: false
    intent: cost              # cost | declaration
    rung: 0                   # this component's rung; park ascending
    consumerRungs: []         # rungs of everything that READS this component
    floor: 0
    reason: ""                # REQUIRED — a park with no stated reason is a
                              # forgotten one; nothing re-reads a header
    nodeSelectorSinkKey: park.pleme.io/disabled
    target:                   # OR park.targets: [ ... ] for several
      objectKind: Deployment  # Deployment|StatefulSet|ReplicaSet|DaemonSet|
                              # Job|CronJob|HelmRelease|Kustomization|
                              # CustomResource|NodePool
      name: ""                # default: pleme-lib.fullname
      namespace: ""           # default: .Release.Namespace
      ownerKind: none         # none|helm|operator|autoscaler|flux
      autoscaler: keda        # keda|hpa — only read when ownerKind=autoscaler
      zeroSafe: false         # MEASURED, see above
      operatorReconciles: false
      valuesPath: ""          # default /spec/values/replicaCount (chartReplicas)
                              # or /spec/replicas (scaleSubresource)
      existingPostRenderers: null   # REQUIRED for postRenderer
      hostsRecoveryPath: null       # REQUIRED for provisionerCeiling
      hpaScaleToZeroGate: false     # the alpha feature gate; see hpaFloor
      autoscalerName: ""      # the ScaledObject / HPA object's own name, when it
                              # differs from the workload's; default: name
      rendered:               # REQUIRED for postRenderer — the rendered object
        kind: Deployment
        name: ""
    exempt:
      admitsOwnUnpark: false
      carriesOutThePark: false
      universalDependency: false
      recoveryPathOnly: false
      pinnedToParkedCapacity: false
    suspend:                  # REQUIRED for intent=declaration
      blockedBy: ""           # stable slug naming the blocker
      blockedClearing: ""     # one of clearingPaths — a CLOSED set
      blockedSince: ""        # ISO date
      clearingPaths: [operator-reconcile, upstream-fix, artifact-publish, manual-apply]
*/}}

{{/* ── verb dispatch: validate the inputs, return the verb ─────────────── */}}
{{- define "pleme-lib.park.verb" -}}
{{- $t := .target | default dict -}}
{{- $ctx := .ctx | default "park" -}}
{{- $intent := .intent | default "cost" -}}
{{- $kinds := list "Deployment" "StatefulSet" "ReplicaSet" "DaemonSet" "Job" "CronJob" "HelmRelease" "Kustomization" "CustomResource" "NodePool" -}}
{{- $owners := list "none" "helm" "operator" "autoscaler" "flux" -}}
{{- $kind := $t.objectKind | default "" -}}
{{- $owner := $t.ownerKind | default "none" -}}
{{- if not (has $intent (list "cost" "declaration")) -}}
{{- fail (printf "pleme-lib.park (%s): park.intent is %q — must be cost (floor the pods) or declaration (park a correct-but-unrealizable declaration). They are different acts: declaration-parking stops reconciliation and leaves the workload running." $ctx $intent) -}}
{{- end -}}
{{- if not (has $kind $kinds) -}}
{{- fail (printf "pleme-lib.park (%s): park.target.objectKind is %q — must be one of %s. The verb table dispatches on this; an unrecognised kind has no floor verb and would render a park that floors nothing." $ctx $kind (join "|" $kinds)) -}}
{{- end -}}
{{- if not (has $owner $owners) -}}
{{- fail (printf "pleme-lib.park (%s): park.target.ownerKind is %q — must be one of %s. This names who WRITES the replica field at runtime; guessing it is how a park gets reverted on the next reconcile." $ctx $owner (join "|" $owners)) -}}
{{- end -}}

{{- $verb := "" -}}
{{- if eq $intent "declaration" -}}
  {{- if has $kind (list "Job" "CronJob") -}}{{- $verb = "jobSuspend" -}}
  {{- else if has $kind (list "HelmRelease" "Kustomization") -}}{{- $verb = "fluxSuspend" -}}
  {{- else -}}
  {{- fail (printf "pleme-lib.park (%s): park.intent=declaration needs a RECONCILED declaration to suspend (HelmRelease|Kustomization|Job|CronJob); park.target.objectKind is %q. A bare workload object has no suspend field — use park.intent=cost." $ctx $kind) -}}
  {{- end -}}
{{- else -}}
  {{- if eq $owner "autoscaler" -}}
    {{- $as := $t.autoscaler | default "keda" -}}
    {{- if eq $as "hpa" -}}{{- $verb = "hpaFloor" -}}
    {{- else if eq $as "keda" -}}{{- $verb = "pausedReplicas" -}}
    {{- else -}}
    {{- fail (printf "pleme-lib.park (%s): park.target.autoscaler is %q — must be keda (verb pausedReplicas) or hpa (verb hpaFloor). The two floors are not interchangeable: only the paused-replicas annotation pins a target regardless of what its triggers report." $ctx $as) -}}
    {{- end -}}
  {{- else if eq $kind "DaemonSet" -}}{{- $verb = "nodeSelectorSink" -}}
  {{- else if has $kind (list "Job" "CronJob") -}}{{- $verb = "jobSuspend" -}}
  {{- else if eq $kind "NodePool" -}}{{- $verb = "provisionerCeiling" -}}
  {{- else if $t.operatorReconciles -}}
    {{- if eq $owner "helm" -}}{{- $verb = "chartReplicas" -}}{{- else -}}{{- $verb = "scaleSubresource" -}}{{- end -}}
  {{- else if eq $kind "HelmRelease" -}}
    {{- if $t.zeroSafe -}}{{- $verb = "chartReplicas" -}}{{- else -}}{{- $verb = "postRenderer" -}}{{- end -}}
  {{- else if eq $kind "CustomResource" -}}{{- $verb = "scaleSubresource" -}}
  {{- else if has $kind (list "Deployment" "StatefulSet" "ReplicaSet") -}}{{- $verb = "replicas" -}}
  {{- else -}}
  {{- fail (printf "pleme-lib.park (%s): no floor verb exists for park.target.objectKind=%q with park.target.ownerKind=%q. Name the surface that actually owns its replica count — set park.target.ownerKind, or park the declaration that renders it instead." $ctx $kind $owner) -}}
  {{- end -}}
{{- end -}}

{{- /* ── verb legality: refusals that depend on the resolved verb ────── */ -}}
{{- if and $t.operatorReconciles (eq $owner "helm") (not $t.zeroSafe) -}}
{{- fail (printf "pleme-lib.park (%s): no safe verb exists. park.target.operatorReconciles=true means a controller rewrites the rendered object, so a postRenderer on it is reverted on the next reconcile; that leaves only the chart value the controller reads, and park.target.zeroSafe=false says the chart swallows a literal 0. Render the chart with 0 and read the output: if it emits 1, fix the chart's zero-value handling or move the pin, then set park.target.zeroSafe=true." $ctx) -}}
{{- end -}}
{{- if eq $verb "postRenderer" -}}
  {{- if kindIs "invalid" $t.existingPostRenderers -}}
  {{- fail (printf "pleme-lib.park (%s): park.target.existingPostRenderers is REQUIRED for the postRenderer verb and has no default. A JSON-patch `add` at an array's own path REPLACES that array, so guessing false would silently discard whatever postRenderers the target already carries. Read the live object and declare true (append with the /- form) or false (create the list)." $ctx) -}}
  {{- end -}}
  {{- $r := $t.rendered | default dict -}}
  {{- if not $r.kind -}}
  {{- fail (printf "pleme-lib.park (%s): park.target.rendered.kind is required for the postRenderer verb — a postRenderer patches the RENDERED object, not the release, so it needs that object's kind (Deployment|StatefulSet|DaemonSet)." $ctx) -}}
  {{- end -}}
  {{- if not $r.name -}}
  {{- fail (printf "pleme-lib.park (%s): park.target.rendered.name is required for the postRenderer verb. Read the rendered name from the live cluster rather than deriving it — a chart's own fullname prefix is not always what it emits." $ctx) -}}
  {{- end -}}
{{- end -}}
{{- if eq $verb "provisionerCeiling" -}}
  {{- if kindIs "invalid" $t.hostsRecoveryPath -}}
  {{- fail (printf "pleme-lib.park (%s): park.target.hostsRecoveryPath is REQUIRED for the provisionerCeiling verb and has no default. A ceiling is not an evictor — it reaps nothing on its own — but a ceiling of zero means nothing can REPLACE a node that consolidation reclaims. Declare whether this pool hosts any part of the recovery path." $ctx) -}}
  {{- end -}}
  {{- if $t.hostsRecoveryPath -}}
  {{- fail (printf "pleme-lib.park (%s): refusing a provisionerCeiling on a pool with park.target.hostsRecoveryPath=true. Measured on one production cluster, 2026-08: a zero ceiling on the pools hosting DNS, the reconcilers, the CSI controller and the node provisioner itself stranded dozens of pods the moment consolidation reclaimed a node — and a cluster whose provisioner cannot schedule cannot provision its way out. Recovery took manual patches and hand-removing a registration taint. Give this pool a real non-zero limit, or set park.enabled=false for it." $ctx) -}}
  {{- end -}}
{{- end -}}
{{- $verb -}}
{{- end -}}

{{/* ── every refusal that is not verb-local; emits nothing on success ──── */}}
{{- define "pleme-lib.park.guards" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "park" -}}
{{- $g := $root.Values.global | default dict -}}
{{- $p := $root.Values.park | default $g.park | default dict -}}
{{- if $p.enabled -}}

{{- /* A park with no stated reason becomes a forgotten one. The reason lives
       in a header nobody re-reads, and the day the need clears there is no
       signal — so the reason is carried on the object instead. */ -}}
{{- if not $p.reason -}}
{{- fail (printf "pleme-lib.park (%s): park.reason is required — one line saying why this is floored. A park whose reason lives only in a commit message or a file header is one nobody can safely unpark, because nothing re-reads it and nothing signals when the need has cleared." $ctx) -}}
{{- end -}}

{{- /* ── the exemption predicate ─────────────────────────────────────── */ -}}
{{- $e := $p.exempt | default dict -}}
{{- if $e.admitsOwnUnpark -}}
{{- fail (printf "pleme-lib.park (%s): refusing — park.exempt.admitsOwnUnpark is true. This component admits the very update that LIFTS the park, so parking it seals the park shut: the Fail-policy webhook has no endpoints, the update is rejected, and nothing in git can reopen it. Verified live on one production cluster, 2026-08. Set park.enabled=false for this component." $ctx) -}}
{{- end -}}
{{- if $e.carriesOutThePark -}}
{{- fail (printf "pleme-lib.park (%s): refusing — park.exempt.carriesOutThePark is true. This is the controller whose reconcile turns the park's declaration into floored pods; parking it in the same commit is a race the park loses. Measured on one production cluster, 2026-08: the release controller waited on a status the parked operator could no longer advance, timed out, and remediation rolled the park back to the pre-park replica count. Park it in a LATER rung, or set park.enabled=false." $ctx) -}}
{{- end -}}
{{- if $e.universalDependency -}}
{{- fail (printf "pleme-lib.park (%s): refusing — park.exempt.universalDependency is true. Every workload depends on this by construction, so NO rung is high enough: any reschedule, node roll or restart during the park then fails against it. Measured on one production cluster, 2026-08 — hours of pull failures for the saving of one small pod, while the only recurring charge billed anyway. Set park.enabled=false for this component." $ctx) -}}
{{- end -}}
{{- if $e.recoveryPathOnly -}}
{{- fail (printf "pleme-lib.park (%s): refusing — park.exempt.recoveryPathOnly is true. This IS the unpark path (the reconciler, the provisioner, the issuer, the secret syncer). Flooring it converts recovery from a git revert into an out-of-band change. Set park.enabled=false for this component." $ctx) -}}
{{- end -}}
{{- if $e.pinnedToParkedCapacity -}}
{{- fail (printf "pleme-lib.park (%s): refusing — park.exempt.pinnedToParkedCapacity is true. It is pinned to capacity this park removes, so it would sit Pending forever: an unfinished park, not a steady state. Either free the pin or set park.enabled=false for this component." $ctx) -}}
{{- end -}}

{{- /* ── PRECEDENCE: park > scaleToZero > breathe ─────────────────────── */ -}}
{{- $targets := $p.targets | default (list ($p.target | default dict)) -}}
{{- $verbs := list -}}
{{- range $t := $targets -}}
{{- $verbs = append $verbs (include "pleme-lib.park.verb" (dict "target" $t "intent" ($p.intent | default "cost") "ctx" $ctx)) -}}
{{- end -}}
{{- $rivals := list -}}
{{- if ($root.Values.scaleToZero).enabled -}}{{- $rivals = append $rivals "scaleToZero.enabled" -}}{{- end -}}
{{- if ($root.Values.breathability).enabled -}}{{- $rivals = append $rivals "breathability.enabled" -}}{{- end -}}
{{- if ($root.Values.autoscaling).enabled -}}{{- $rivals = append $rivals "autoscaling.enabled" -}}{{- end -}}
{{- if $rivals -}}
  {{- range $v := $verbs -}}
  {{- if has $v (list "replicas" "chartReplicas" "postRenderer" "scaleSubresource") -}}
  {{- fail (printf "pleme-lib.park (%s): park.enabled is true while %s also owns this workload's replica count, and the resolved verb %q writes a number the autoscaler lifts on its next tick. Precedence is fixed — park > scaleToZero > breathe — so a park an autoscaler can undo is not a park. Either set park.target.ownerKind=autoscaler (verb pausedReplicas, which pins the target regardless of what any trigger reports) or set %s=false for the duration of the park." $ctx (join " and " $rivals) $v (first $rivals)) -}}
  {{- end -}}
  {{- end -}}
{{- end -}}

{{- /* ── verb preconditions ──────────────────────────────────────────
       LIFTED here from the emit path 2026-08-29. Both refusals below used to
       live beside the patch that emits them, so an entry point that computed
       verbs WITHOUT emitting — a lint, a dry-run, a chart that only wants the
       annotations — skipped them entirely and reported a park that would fail
       at apply. A guard reachable only from one of several entry points is a
       guard that is sometimes not there. Every entry point calls THIS block. */ -}}
{{- $seenPath := dict -}}
{{- range $t := $targets -}}
{{- $tv := include "pleme-lib.park.verb" (dict "target" $t "intent" ($p.intent | default "cost") "ctx" $ctx) -}}

{{- /* minReplicas=0 is rejected by the API server unless an alpha gate is on */ -}}
{{- if eq $tv "hpaFloor" -}}
{{- if and (eq (int ($p.floor | default 0)) 0) (not $t.hpaScaleToZeroGate) -}}
{{- fail (printf "pleme-lib.park (%s): the hpaFloor verb cannot write minReplicas=0 — the API server rejects a HorizontalPodAutoscaler below 1 unless the HPAScaleToZero alpha feature gate is on, so this park would fail at apply time. Set park.floor to 1, or declare park.target.hpaScaleToZeroGate=true once the gate is verified on the cluster, or park through the paused-replicas annotation instead." $ctx) -}}
{{- end -}}
{{- end -}}

{{- /* two patches on one path is a conflict neither author sees */ -}}
{{- $tpath := $t.valuesPath | default "/spec/replicas" -}}
{{- if eq $tv "provisionerCeiling" -}}{{- $tpath = ($t.valuesPath | default "/spec/limits") -}}{{- end -}}
{{- $tkey := printf "%s/%s/%s#%s" ($t.kind | default "?") ($t.namespace | default "?") ($t.name | default "?") $tpath -}}
{{- if hasKey $seenPath $tkey -}}
{{- fail (printf "pleme-lib.park (%s): two park targets both write %s on %s/%s/%s. Two patches on the same path is a conflict: the second apply collides, and if they land from separate components neither one's author sees it. Merge them into one target, or park the second through a different surface." $ctx $tpath ($t.kind | default "?") ($t.namespace | default "?") ($t.name | default "?")) -}}
{{- end -}}
{{- $_ := set $seenPath $tkey true -}}
{{- end -}}

{{- /* ── ORDERING: a reader must park at or before what it reads ─────── */ -}}
{{- $rung := $p.rung | default 0 -}}
{{- range $cr := ($p.consumerRungs | default list) -}}
{{- if gt (int $cr) (int $rung) -}}
{{- fail (printf "pleme-lib.park (%s): park.consumerRungs declares a reader at rung %d while this component parks at rung %d. Park descends by ASCENDING rung, so that reader is still running when this floors, and every connection, query or pull it makes then fails against a service with nothing listening. Nothing else checks this edge. Raise park.rung above every entry in park.consumerRungs, or move that reader to an earlier rung." $ctx (int $cr) (int $rung)) -}}
{{- end -}}
{{- end -}}

{{- /* ── a suspended DECLARATION must name its blocker ────────────────── */ -}}
{{- if eq ($p.intent | default "cost") "declaration" -}}
{{- $s := $p.suspend | default dict -}}
{{- $paths := $s.clearingPaths | default (list "operator-reconcile" "upstream-fix" "artifact-publish" "manual-apply") -}}
{{- if not $s.blockedBy -}}
{{- fail (printf "pleme-lib.park (%s): park.suspend.blockedBy is required for park.intent=declaration — a stable slug naming what is blocking. Suspending a correct-but-unrealizable declaration is right; leaving the reason in prose is the debt: nothing re-reads it, and the day the blocker clears there is no signal, so a parked declaration quietly becomes a forgotten one." $ctx) -}}
{{- end -}}
{{- if not $s.blockedSince -}}
{{- fail (printf "pleme-lib.park (%s): park.suspend.blockedSince is required for park.intent=declaration (ISO date). Without it there is no way to tell a suspension made last week from one made last year, and both read identically." $ctx) -}}
{{- end -}}
{{- if not (has ($s.blockedClearing | default "") $paths) -}}
{{- fail (printf "pleme-lib.park (%s): park.suspend.blockedClearing is %q — must be one of %s. The set is CLOSED on purpose: an unrecognised value is indistinguishable from a typo, and both index a clearing path nobody can walk. Declare additional paths in park.suspend.clearingPaths; never guess one to clear a line." $ctx ($s.blockedClearing | default "") (join "|" $paths)) -}}
{{- end -}}
{{- end -}}

{{- end -}}
{{- end -}}

{{/*
pleme-lib.park.replicasField — emit `replicas: 0`, or nothing at all.

Sibling of pleme-lib.scaleToZero.replicasField, and it OUTRANKS it: when a park
owns this chart's own workload, park writes the field and the activation policy
does not. When park does not own it, this emits nothing and the caller falls
through to its usual replicas source.

Usage, inside a Deployment/StatefulSet spec:
  {{- include "pleme-lib.park.replicasField" (dict "root" $ "ctx" "my-chart") | nindent 2 }}
*/}}
{{- define "pleme-lib.park.replicasField" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "park" -}}
{{- $g := $root.Values.global | default dict -}}
{{- $p := $root.Values.park | default $g.park | default dict -}}
{{- if $p.enabled -}}
{{- include "pleme-lib.park.guards" (dict "root" $root "ctx" $ctx) -}}
{{- /* `target` is this chart's OWN workload; `targets` is the out-of-chart
       patch list. A chart that declares only the plural form still gets its
       object-level artifacts from the first entry rather than from an empty
       dict that would fail as an unrecognised kind. */ -}}
{{- $t := first ($p.targets | default (list ($p.target | default dict))) -}}
{{- $verb := include "pleme-lib.park.verb" (dict "target" $t "intent" ($p.intent | default "cost") "ctx" $ctx) -}}
{{- if has $verb (list "replicas" "chartReplicas" "scaleSubresource") -}}
{{- /* Reuses pleme-lib.scaleToZero.num: sprig's `default` treats integer 0 as
       empty, which is exactly the value a park is made of. */ -}}
replicas: {{ include "pleme-lib.scaleToZero.num" (list $p.floor 0) }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
pleme-lib.park.annotations — the annotation block a parked object carries.

Two jobs. It carries the KEDA paused-replicas floor for the pausedReplicas verb
— the only floor that survives a live autoscaler — and it carries the park
RECEIPT, so "what is parked, by which verb, at which rung, since when, and
cleared by what" is readable off the object instead of living in a file header
nobody re-reads. Feed it into a partial that accepts annotations (for example
scaleToZero.annotations) or splice it into metadata directly.

Usage:
  {{- include "pleme-lib.park.annotations" (dict "root" $ "ctx" "my-chart") | nindent 4 }}
*/}}
{{- define "pleme-lib.park.annotations" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "park" -}}
{{- $g := $root.Values.global | default dict -}}
{{- $p := $root.Values.park | default $g.park | default dict -}}
{{- if $p.enabled -}}
{{- include "pleme-lib.park.guards" (dict "root" $root "ctx" $ctx) -}}
{{- /* `target` is this chart's OWN workload; `targets` is the out-of-chart
       patch list. A chart that declares only the plural form still gets its
       object-level artifacts from the first entry rather than from an empty
       dict that would fail as an unrecognised kind. */ -}}
{{- $t := first ($p.targets | default (list ($p.target | default dict))) -}}
{{- $verb := include "pleme-lib.park.verb" (dict "target" $t "intent" ($p.intent | default "cost") "ctx" $ctx) -}}
{{- $floor := include "pleme-lib.scaleToZero.num" (list $p.floor 0) -}}
park.pleme.io/verb: {{ $verb | quote }}
park.pleme.io/intent: {{ ($p.intent | default "cost") | quote }}
park.pleme.io/rung: {{ ($p.rung | default 0) | quote }}
park.pleme.io/reason: {{ $p.reason | quote }}
{{- if eq $verb "pausedReplicas" }}
autoscaling.keda.sh/paused-replicas: {{ $floor | quote }}
{{- end }}
{{- if eq ($p.intent | default "cost") "declaration" }}
{{- $s := $p.suspend | default dict }}
park.pleme.io/blocked-by: {{ $s.blockedBy | quote }}
park.pleme.io/blocked-clearing: {{ $s.blockedClearing | quote }}
park.pleme.io/blocked-since: {{ $s.blockedSince | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
pleme-lib.park.patches — the reconciler-side patch list, generated from the
verb table rather than hand-written.

Emits the body of a `patches:` list: one entry per target, each an RFC 6902
JSON patch or a strategic-merge document, addressed to the object the resolved
verb actually owns. This is the out-of-chart case — parking a release this
chart does not render.

Usage, inside a kustomize Component or a reconciler's spec.patches:
  patches:
    {{- include "pleme-lib.park.patches" (dict "root" $ "ctx" "my-park") | nindent 4 }}
*/}}
{{- define "pleme-lib.park.patches" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "park" -}}
{{- $g := $root.Values.global | default dict -}}
{{- $p := $root.Values.park | default $g.park | default dict -}}
{{- if $p.enabled -}}
{{- include "pleme-lib.park.guards" (dict "root" $root "ctx" $ctx) -}}
{{- $intent := $p.intent | default "cost" -}}
{{- $floor := include "pleme-lib.scaleToZero.num" (list $p.floor 0) -}}
{{- $sinkKey := $p.nodeSelectorSinkKey | default "park.pleme.io/disabled" -}}
{{- $targets := $p.targets | default (list ($p.target | default dict)) -}}
{{- $seen := dict -}}
{{- range $t := $targets -}}
{{- $verb := include "pleme-lib.park.verb" (dict "target" $t "intent" $intent "ctx" $ctx) -}}
{{- $name := $t.name | default (include "pleme-lib.fullname" $root) -}}
{{- $ns := $t.namespace | default $root.Release.Namespace -}}
{{- $kind := $t.objectKind -}}
{{- $r := $t.rendered | default dict -}}
{{- /* An autoscaler floor is written on the AUTOSCALER, never on the workload:
       patching the workload's own replica field is exactly the write the
       autoscaler lifts on its next tick. objectKind names the workload, so the
       addressed kind and name are re-pointed here. */ -}}
{{- if eq $verb "pausedReplicas" -}}
{{- $kind = "ScaledObject" -}}{{- $name = ($t.autoscalerName | default $name) -}}
{{- else if eq $verb "hpaFloor" -}}
{{- $kind = "HorizontalPodAutoscaler" -}}{{- $name = ($t.autoscalerName | default $name) -}}
{{- end -}}

{{- /* the path this entry will write — the collision key */ -}}
{{- $path := "" -}}
{{- if eq $verb "replicas" -}}{{- $path = "/spec/replicas" -}}
{{- else if eq $verb "chartReplicas" -}}{{- $path = ($t.valuesPath | default "/spec/values/replicaCount") -}}
{{- else if eq $verb "scaleSubresource" -}}{{- $path = ($t.valuesPath | default "/spec/replicas") -}}
{{- else if eq $verb "postRenderer" -}}{{- $path = (ternary "/spec/postRenderers/0/kustomize/patches/-" "/spec/postRenderers" $t.existingPostRenderers) -}}
{{- else if eq $verb "hpaFloor" -}}{{- $path = "/spec/minReplicas" -}}
{{- else if eq $verb "fluxSuspend" -}}{{- $path = "/spec/suspend" -}}
{{- else if eq $verb "jobSuspend" -}}{{- $path = "/spec/suspend" -}}
{{- else if eq $verb "pausedReplicas" -}}{{- $path = "/metadata/annotations" -}}
{{- else if eq $verb "nodeSelectorSink" -}}{{- $path = "/spec/template/spec/nodeSelector" -}}
{{- else if eq $verb "provisionerCeiling" -}}{{- $path = ($t.valuesPath | default "/spec/limits") -}}
{{- end -}}
{{- $key := printf "%s/%s/%s#%s" $kind $ns $name $path -}}
{{- if hasKey $seen $key -}}
{{- fail (printf "pleme-lib.park (%s): two park targets both write %s on %s/%s/%s. Two patches on the same path is a conflict: the second apply collides, and if they land from separate components neither one's author sees it. Merge them into one target, or park the second through a different surface." $ctx $path $kind $ns $name) -}}
{{- end -}}
{{- $_ := set $seen $key true -}}

{{/* the hpaFloor and same-path guards moved into pleme-lib.park.guards — see
     the note there. Left here as a marker so nobody re-adds them to the emit
     path. */}}
- target:
    kind: {{ $kind }}
    name: {{ $name }}
    namespace: {{ $ns }}
  patch: |
{{- if eq $verb "replicas" }}
    - op: replace
      path: /spec/replicas
      value: {{ $floor }}
{{- else if eq $verb "chartReplicas" }}
    - op: replace
      path: {{ $path }}
      value: {{ $floor }}
{{- else if eq $verb "scaleSubresource" }}
    - op: replace
      path: {{ $path }}
      value: {{ $floor }}
{{- else if eq $verb "hpaFloor" }}
    - op: replace
      path: /spec/minReplicas
      value: {{ $floor }}
{{- else if eq $verb "fluxSuspend" }}
    - op: add
      path: /spec/suspend
      value: true
{{- else if eq $verb "jobSuspend" }}
    apiVersion: batch/v1
    kind: {{ $kind }}
    metadata:
      name: {{ $name }}
    spec:
      suspend: true
{{- else if eq $verb "pausedReplicas" }}
    apiVersion: keda.sh/v1alpha1
    kind: ScaledObject
    metadata:
      name: {{ $name }}
      annotations:
        autoscaling.keda.sh/paused-replicas: {{ $floor | quote }}
{{- else if eq $verb "nodeSelectorSink" }}
    apiVersion: apps/v1
    kind: DaemonSet
    metadata:
      name: {{ $name }}
    spec:
      template:
        spec:
          nodeSelector:
            {{ $sinkKey }}: "true"
{{- else if eq $verb "provisionerCeiling" }}
    - op: replace
      path: {{ $path }}
      value: {nodes: "0"}
{{- else if eq $verb "postRenderer" }}
{{- if $t.existingPostRenderers }}
    - op: add
      path: /spec/postRenderers/0/kustomize/patches/-
      value:
        target:
          kind: {{ $r.kind }}
          name: {{ $r.name }}
        patch: |
          apiVersion: apps/v1
          kind: {{ $r.kind }}
          metadata:
            name: {{ $r.name }}
          spec:
            replicas: {{ $floor }}
{{- else }}
    - op: add
      path: /spec/postRenderers
      value:
        - kustomize:
            patches:
              - target:
                  kind: {{ $r.kind }}
                  name: {{ $r.name }}
                patch: |
                  apiVersion: apps/v1
                  kind: {{ $r.kind }}
                  metadata:
                    name: {{ $r.name }}
                  spec:
                    replicas: {{ $floor }}
{{- end }}
{{- end }}
{{- /* ── the remediation disarm, emitted with every release-mediated park ──
       A post-upgrade hook that waits for the stack to come up healthy is
       exactly what a park prevents. Without this the upgrade times out, the
       release is marked failed, remediation rolls it back, and every workload
       returns to its pre-park count and crash-loops against datastores on
       their way down — the park undone by its own rollback, measured on one
       production cluster, 2026-08. */ -}}
{{- if has $verb (list "chartReplicas" "postRenderer") }}
- target:
    kind: {{ $kind }}
    name: {{ $name }}
    namespace: {{ $ns }}
  patch: |
    - op: add
      path: /spec/install/disableHooks
      value: true
    - op: add
      path: /spec/upgrade/disableHooks
      value: true
    - op: replace
      path: /spec/upgrade/remediation/remediateLastFailure
      value: false
    - op: replace
      path: /spec/upgrade/remediation/retries
      value: 0
{{- end }}
{{/* ONE trailing newline per entry. Every branch above closes on a trimming
     action, which eats the newline after its last line — without this the
     next iteration's `- target:` lands on the previous entry's last value and
     the whole list silently parses as one malformed item. */}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
pleme-lib.park — the park RECEIPT.

Runs every guard, then records what was parked, by which verb, at which rung,
why, and — for a suspended declaration — what would clear it. The receipt is an
object in the cluster rather than prose in a header, because the debt a park
accrues is not the floor: it is that the reason stops being re-read and the
park quietly becomes permanent.

Usage in a chart's templates/park.yaml:
  {{- include "pleme-lib.park" (dict "root" $ "ctx" "my-chart") }}
*/}}
{{- define "pleme-lib.park" -}}
{{- $root := .root -}}
{{- $ctx := .ctx | default "park" -}}
{{- $g := $root.Values.global | default dict -}}
{{- $p := $root.Values.park | default $g.park | default dict -}}
{{- if $p.enabled -}}
{{- include "pleme-lib.park.guards" (dict "root" $root "ctx" $ctx) -}}
{{- $intent := $p.intent | default "cost" -}}
{{- $targets := $p.targets | default (list ($p.target | default dict)) -}}
{{- $fullname := include "pleme-lib.fullname" $root -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $fullname }}-park
  labels:
    {{- include "pleme-lib.labels" $root | nindent 4 }}
  annotations:
    {{- include "pleme-lib.park.annotations" (dict "root" $root "ctx" $ctx) | nindent 4 }}
data:
  intent: {{ $intent | quote }}
  rung: {{ ($p.rung | default 0) | quote }}
  floor: {{ (include "pleme-lib.scaleToZero.num" (list $p.floor 0)) | quote }}
  reason: {{ $p.reason | quote }}
  {{- /* Unpark is the reverse traversal, stated on the object so nobody has to
         reconstruct it: park ascends the rungs, unpark descends them. */}}
  unparkOrder: "descending-rung"
  verbs: |
    {{- range $t := $targets }}
    {{ $t.objectKind }}/{{ $t.name | default $fullname }}: {{ include "pleme-lib.park.verb" (dict "target" $t "intent" $intent "ctx" $ctx) }}
    {{- end }}
  {{- if $p.consumerRungs }}
  consumerRungs: {{ (join "," $p.consumerRungs) | quote }}
  {{- end }}
  {{- if eq $intent "declaration" }}
  {{- $s := $p.suspend | default dict }}
  blockedBy: {{ $s.blockedBy | quote }}
  blockedClearing: {{ $s.blockedClearing | quote }}
  blockedSince: {{ $s.blockedSince | quote }}
  {{- end }}
{{- end -}}
{{- end -}}
