{{/*
pleme-lib: namespace-scoped RBAC primitives — Role + RoleBinding

Renders one or more namespace-scoped Role + RoleBinding pairs from a values map,
each binding to one or more subjects (typically a ServiceAccount in the same
namespace). Consumers structure values as:

  rbac:
    roles:
      <name>:                 # rendered as Role/<name> + RoleBinding/<name>
        rules:
          - apiGroups: [""]
            resources: ["pods", "namespaces"]
            verbs: ["get", "list", "watch"]
        subjects:
          - kind: ServiceAccount
            name: my-sa
            # namespace defaults to release namespace when omitted
        # roleRef defaults to the rendered Role/<name>; override only for cross-binding patterns

Use this when a chart's primary SA needs in-namespace verbs. For cluster-scoped
RBAC use `pleme-lib.clusterRBAC` (below).

  rbac:
    clusterRoles:
      <name>:                      # ClusterRole/<name> (+ ClusterRoleBinding unless binding: false)
        rules: [ ... ]
        # aggregateLabels:         # merged onto the ClusterRole's labels so an aggregated
        #   rbac.crossplane.io/aggregate-to-crossplane: "true"   # role (e.g. crossplane's) absorbs these rules
        # aggregationRule: { ... } # for a ClusterRole that is itself an aggregator
        # binding: false           # aggregation-only ClusterRole: emit no ClusterRoleBinding
        subjects:
          - { kind: ServiceAccount, name: my-sa }                # namespace defaults to release ns
          - { kind: Group, name: "system:masters" }              # Group/User get apiGroup, no namespace
*/}}

{{- define "pleme-lib.namespacedRBAC" -}}
{{- range $name, $spec := (.Values.rbac).roles }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $name | kebabcase }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.attestationAnnotations" $) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
rules:
  {{- toYaml $spec.rules | nindent 2 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $name | kebabcase }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ default ($name | kebabcase) (($spec.roleRef).name) }}
subjects:
  {{- range $spec.subjects }}
  - kind: {{ default "ServiceAccount" .kind }}
    name: {{ .name }}
    namespace: {{ default (include "pleme-lib.namespace" $) .namespace }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.clusterRBAC — cluster-scoped ClusterRole (+ ClusterRoleBinding) pairs from a
.Values.rbac.clusterRoles map. Mirror of namespacedRBAC. Fleet-generic: any Composition
whose core-controller does SSA against a vendor MR group needs an aggregate-to-crossplane
ClusterRole; `aggregateLabels` is the typed slot for that. `binding: false` emits the
ClusterRole only (aggregation-only). ServiceAccount subjects get a namespace; Group/User
subjects get an apiGroup.
*/}}
{{- define "pleme-lib.clusterRBAC" -}}
{{- range $name, $spec := (.Values.rbac).clusterRoles }}
{{/* A ClusterRole is cluster-wide by construction — no scope field to consult,
     no namespace to fall back on — so every rule here sits at the reach the
     guard checks. This map does not route through pleme-lib.rbac.validate,
     which is precisely why the call belongs here as well as there. */}}
{{- include "pleme-lib.rbac.namespaceDeleteBound" (dict "rules" ($spec.rules | default list) "where" (printf "rbac.clusterRoles[%q].rules" $name)) -}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ $name | kebabcase }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
    {{- with $spec.aggregateLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with (include "pleme-lib.attestationAnnotations" $) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
{{- with $spec.aggregationRule }}
aggregationRule:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $spec.rules }}
rules:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if or (not (hasKey $spec "binding")) $spec.binding }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ $name | kebabcase }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ default ($name | kebabcase) (($spec.roleRef).name) }}
subjects:
  {{- range $spec.subjects }}
  - kind: {{ default "ServiceAccount" .kind }}
    name: {{ .name }}
    {{- if eq (default "ServiceAccount" .kind) "ServiceAccount" }}
    namespace: {{ default (include "pleme-lib.namespace" $) .namespace }}
    {{- else }}
    apiGroup: {{ .apiGroup | default "rbac.authorization.k8s.io" }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.rbac — ONE scoped identity: ServiceAccount + (Role|ClusterRole) + binding.

The two templates above are MAPS: N roles from a values map, each authored in
full. This one is the opposite shape and the one to reach for first — a single
workload's own identity, where the only question is HOW FAR IT REACHES. That
question has exactly three answers, `rbac.scope` names which, and the placement
of every rule follows from it rather than from what the author happened to type.

They coexist under one `rbac:` key (`roles`/`clusterRoles` vs
`scope`/`rules`/`observe`/`mutate`) and a chart may use both. A key in either map
that kebabcases to this identity's own name is refused: the collision would only
surface as a duplicate-resource error at apply time, long after the render.

WHY A SCOPE EXISTS AT ALL, and why it has NO DEFAULT.
A chart that emits ClusterRole unconditionally is unusable on borrowed ground —
a cluster we are a guest in, where a cluster-wide watch of every namespace is
precisely the thing we promise not to do. Measured on one such cluster, 2026-08:
the workaround was a hand-rolled namespaced copy of an entire operator inside
another chart's templates, i.e. a second declaration of one controller. A
default of `cluster` would keep producing that copy, silently, the first time
someone installs somewhere new — so `rbac.scope` is required and the render
fails without it. The decision is made once, in values, where a reviewer sees it.

  namespaced     Role + RoleBinding in the release namespace. Nothing else.
  cluster        ClusterRole + ClusterRoleBinding. Our own ground.
  guest-cluster  Borrowed ground that must still reconcile OUR kind in
                 namespaces minted after install. Split by API-group ownership:
                 `rbac.ownApiGroups` reach cluster-wide (the host owns zero
                 objects of those kinds, so the grant reads nothing of theirs,
                 and it is what lets the controller watch); everything else —
                 Secrets, ConfigMaps, workloads, anything that could touch host
                 data — is bound to the release namespace alone.

THE PAIRING LAW, enforced here with a fail() because prose did not hold it.
The scope decides what the workload is ALLOWED to see; a namespace-restricting
env var decides what it TRIES to see. They are not redundant, and neither alone
is correct:

  namespaced     REQUIRES the env var set. Scope alone yields a workload
                 permitted to see one namespace and still watching them all —
                 it fails on RBAC at runtime, days later, not at render.
  guest-cluster  REQUIRES the env var unset or empty. Measured on one cluster,
                 2026-08: a CR applied into a namespace minted per spawn was
                 accepted by the apiserver and then sat with NO STATUS AT ALL,
                 because the controller had been pinned to one namespace and
                 never saw it. A pinned guest is blind to exactly the namespaces
                 guest-cluster exists to reach. Env var alone yields a workload
                 holding cluster-wide permissions it does not use.

  Both, or neither. `rbac.namespaceEnvVars` is the caller's list of env var
  names that carry that meaning (default: the one universal operator
  convention). Setting it to `[]` is a DECLARATION that this workload has no
  such knob, and switches the pairing check off — write down why, next to it.
  That opt-out is read with `hasKey`, not `default`: an empty list is falsy in
  Go templates, so a `default` filter would rewrite the caller's `[]` back into
  the default and re-arm the check they just switched off. Same shape as a
  `default` rewriting a deliberate 0, and it cost a render here before it was
  caught. An env var with a `valueFrom` counts as restricting (its value is not
  knowable at render time); an env var set to the empty string does not, which
  is the universal spelling of "watch every namespace".

OBSERVE BROAD / MUTATE NARROW — two rule sets, not a convention.
A controller may legitimately watch far wider than it writes. Expressed as one
rule list, the write verbs inherit the read's reach and nobody notices. So they
are separate values keys with separate placement, and `rbac.observe.rules` is
refused a write verb:

  rbac.observe.rules   read-only, placed at the widest reach the scope allows
  rbac.mutate.rules    placed in `rbac.mutate.namespaces` as a Role, ALWAYS,
                       at every scope — narrow is the point

WITHHELD GRANTS ARE DOCUMENTED AT THE POINT OF ABSENCE.
The hardest thing to read in an RBAC file is what is not in it. A grant left out
on purpose and a grant nobody thought of look identical, so the next author
closes the "gap" with a green build and a widened blast radius. `rbac.withheld`
is the typed ledger: each entry needs a `reason`, and it is stamped as an
annotation on the rendered Role, so the absence travels with the live object
rather than living in a file nobody opens. An entry contradicted by the rules
fails the render — a ledger that lies teaches operators to stop reading it.
Receipts from one production cluster, 2026-07/2026-08: a read-only controller
that deliberately does NOT hold `create` on events, and emits findings as
metrics instead, because an Event write would have cost the whole
cannot-mutate-anything guarantee; and an add-on whose upstream chart's
token-review binding was dropped because nothing scraped its metrics endpoint —
a permission granted for a consumer that does not exist.

TRAPS THIS ENCODES so nobody rediscovers them.

  * `readOnly: true` emits get/list/watch and NOTHING else, wildcards included.
    A read-only claim that can still mutate is worse than no claim, because it
    is the claim an operator reads instead of reading the verbs.
  * `resourceNames` does not apply to create/list/watch/deletecollection —
    there is no object name at authorization time for a create, and the others
    authorize a collection. A rule pairing them reads as a narrow grant and
    authorizes NOTHING for those verbs. Refused; split the rule so the width is
    visible. Found the hard way on one cluster, 2026-08.
  * Binding the namespace's `default` ServiceAccount is refused. It hands
    ambient identity to anything that later lands on it.
  * An identity with zero rules is refused. An empty Role reads as a grant.
  * Widening to make an error go away is the anti-pattern: a
    `cannot create resource ... forbidden` that NAMES the kind is the feature.
    Add the kind, never the wildcard.
  * Kubernetes privilege-escalation prevention: a controller that CREATES Roles
    can only grant verbs it already holds. If it mints per-namespace grants for
    another identity, its own rules must be a superset — a fact no template can
    check, and the reason a mint path fails with a confusing 403 long after the
    RBAC looked complete.

Wildcard bans and dedicated-SA requirements at a compliance baseline are NOT
restated here — they live in `pleme-lib.compliance.authz.validate` and
`pleme-lib.compliance.rbac.validate`, and run over the rendered result.

CALL CONVENTION — ONE dict argument:

  {{- include "pleme-lib.rbac" (dict "ctx" .) }}
    ctx    the root context (required)
    rbac   the config dict (optional; defaults to .Values.rbac)
    name   base object name (optional; defaults to pleme-lib.fullname)

VALUES

  rbac:
    create: true
    scope: namespaced | cluster | guest-cluster    # REQUIRED, no default
    readOnly: false
    ownApiGroups: []            # REQUIRED when scope=guest-cluster
    namespaceEnvVars: [WATCH_NAMESPACE]   # [] disables the pairing check
    # env: []                   # defaults to .Values.env

    # ── shape A: one rule set, placed by scope ──
    rules:
      - apiGroups: [""]
        resources: [configmaps]
        verbs: [get, list, watch]

    # ── shape B: broad observe / narrow mutate (not with guest-cluster) ──
    observe:
      rules: []                 # read verbs only
    mutate:
      namespaces: []            # defaults to the release namespace
      rules: []

    withheld:
      - apiGroups: [""]
        resources: [events]
        reason: "an Event write would cost the cannot-mutate guarantee"

    serviceAccount:
      create: true
      name: ""
      annotations: {}
*/}}

{{/* ── enum guard: validate + echo the scope ───────────────────────────── */}}
{{- define "pleme-lib.rbac.scope" -}}
{{- $r := .rbac | default dict -}}
{{- $allowed := list "namespaced" "cluster" "guest-cluster" -}}
{{- $scope := $r.scope | default "" | toString -}}
{{- if not $scope -}}
{{- fail (printf "pleme-lib.rbac: rbac.scope is required — one of %s. There is deliberately no default: a chart defaulting to `cluster` ships a ClusterRole onto borrowed ground the first time it is installed somewhere new, and nothing in the render says so." (join "|" $allowed)) -}}
{{- end -}}
{{- if not (has $scope $allowed) -}}
{{- fail (printf "pleme-lib.rbac: unknown rbac.scope %q — set rbac.scope to one of %s" $scope (join "|" $allowed)) -}}
{{- end -}}
{{- $scope -}}
{{- end -}}

{{/* ── the absence ledger, stamped on every rendered Role/ClusterRole ──── */}}
{{- define "pleme-lib.rbac.ledger" -}}
{{- $r := .rbac | default dict -}}
rbac.pleme.io/scope: {{ .scope | quote }}
{{- if $r.readOnly }}
rbac.pleme.io/read-only: "true"
{{- end }}
{{- with $r.withheld }}
rbac.pleme.io/withheld: {{ toJson . | quote }}
{{- end }}
{{- end -}}

{{/*
pleme-lib.rbac.namespaceDeleteBound — REFUSE an unbounded namespace delete.

★ WHY THIS ONE GRANT GETS ITS OWN GUARD.
Measured, on a real reaper: the delete went out against an ALL-NAMESPACES
client with default delete parameters — no label selector, no ownerReference
precondition, no uid precondition, no never-delete list. The only thing scoping
it was that the name string happened to be right, and Kubernetes answers 404
for a name that does not exist, which the client treated as success. So a WRONG
NAME FAILS SILENTLY: the reaper reports a clean sweep, the intended namespace
is still there, and whatever the wrong name did match is gone.

A namespace delete is also not a leaf operation. It cascades to everything
inside, asynchronously, past the point where the object stops being listed —
so a mistake is neither observable at the moment it is made nor revertible
after it.

RBAC is the ONE render-time place that bound exists. `resourceNames` DOES apply
to `delete` (it is the by-name verb; the inert ones are create / list / watch /
deletecollection, which the sibling guard in `pleme-lib.rbac.validate` already
refuses to pair with it), so the bound is achievable — and a cluster-wide
`namespaces: [delete]` with no resourceNames is the whole blast radius, granted
at render, in a file a reviewer reads.

WHAT THIS DOES NOT DECIDE, deliberately: wildcards. A rule granting
`resources: ["*"]` is a larger and different defect, and it already has an
owner — `pleme-lib.compliance.authz.validate` and
`pleme-lib.compliance.rbac.validate`, which run over the rendered result.
Re-deciding it here would put one rule in two places and let them disagree. So
this guard fires only on an EXPLICIT `namespaces` resource, in the core API
group ("") or under a group wildcard.

WHAT IT CANNOT BOUND, and this is a world-fact rather than one of ours: RBAC
has no "delete only the namespaces you created" predicate. A controller that
MINTS namespaces with generated names cannot be bounded by `resourceNames` at
all — its real bound is a correlation selector on the objects it made
(`pleme-lib.ephemeral.selector`), which is enforced at the DECLARATION and
never at the call. Such a controller belongs at `rbac.scope=namespaced` with
`rbac.mutate.namespaces`, or it takes the unbounded grant knowingly and the
reviewer meets this refusal explaining what it costs.

Arguments (a dict):
  rules  the rule list to check
  where  the values path to name in the message
*/}}
{{- define "pleme-lib.rbac.namespaceDeleteBound" -}}
{{- $where := .where | default "rbac.rules" -}}
{{- $deleteVerbs := list "delete" "deletecollection" "*" -}}
{{- range $i, $rule := (.rules | default list) -}}
{{- $groups := $rule.apiGroups | default list -}}
{{- $resources := $rule.resources | default list -}}
{{- if and (or (has "" $groups) (has "*" $groups)) (has "namespaces" $resources) -}}
{{- $found := list -}}
{{- range $v := ($rule.verbs | default list) -}}
{{- if has $v $deleteVerbs -}}
{{- $found = append $found $v -}}
{{- end -}}
{{- end -}}
{{- if and (gt (len $found) 0) (not (gt (len ($rule.resourceNames | default list)) 0)) -}}
{{- fail (printf "pleme-lib.rbac: %s[%d] grants %v on namespaces at CLUSTER reach with neither resourceNames nor a bounded namespace list. That is authority to delete ANY namespace, and a namespace delete cascades asynchronously to everything inside it — a reaper calling it with the wrong name gets a 404 that reads as success, so the mistake is silent when it is made and irreversible afterwards. Bound it one of three ways: (a) list the exact namespaces in resourceNames — `delete` IS scopable by name; (b) set rbac.scope=namespaced and move the rule to rbac.mutate.rules with rbac.mutate.namespaces naming them; (c) if the names are minted at runtime and cannot be known here, drop the grant — RBAC has no delete-only-what-you-created predicate, so the real bound is a correlation selector on the objects themselves (pleme-lib.ephemeral.selector), enforced by the CALLER and not by this grant. Note that `deletecollection` cannot be bounded by resourceNames at all — it authorizes a collection — so (a) is unavailable for it." $where $i $found) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* ── every refusal, in one place; emits nothing on success ───────────── */}}
{{- define "pleme-lib.rbac.validate" -}}
{{- $ctx := .ctx -}}
{{- $r := .rbac | default dict -}}
{{- $name := .name -}}
{{- $scope := include "pleme-lib.rbac.scope" . -}}
{{- $simple := $r.rules | default list -}}
{{- $obs := (($r.observe) | default dict).rules | default list -}}
{{- $mut := (($r.mutate) | default dict).rules | default list -}}
{{- $mutNs := (($r.mutate) | default dict).namespaces | default list -}}
{{- $split := or (gt (len $obs) 0) (gt (len $mut) 0) (gt (len $mutNs) 0) -}}
{{- $all := concat $simple $obs $mut -}}
{{- $readVerbs := list "get" "list" "watch" -}}

{{/* one shape or the other, never both deciding placement */}}
{{- if and (gt (len $simple) 0) $split -}}
{{- fail "pleme-lib.rbac: rbac.rules is set alongside rbac.observe/rbac.mutate. Pick one shape: rbac.rules for a single rule set placed by rbac.scope, or rbac.observe.rules + rbac.mutate.{namespaces,rules} for the broad-observe / narrow-mutate split. Both means two policies deciding placement for one identity." -}}
{{- end -}}
{{- if and (not (gt (len $simple) 0)) (not $split) -}}
{{- fail "pleme-lib.rbac: rbac.create=true but no rules are declared — rbac.rules, rbac.observe.rules and rbac.mutate.rules are all empty. An identity bound to an empty Role reads as a grant. If the workload genuinely needs no cluster authority, set rbac.create=false and emit the ServiceAccount alone with pleme-lib.serviceaccount." -}}
{{- end -}}
{{- if and (eq $scope "guest-cluster") $split -}}
{{- fail "pleme-lib.rbac: rbac.scope=guest-cluster cannot be combined with rbac.observe/rbac.mutate. guest-cluster already splits broad from narrow — by API-group ownership rather than by verb — and two placement policies cannot both decide. Express the rules in rbac.rules and declare rbac.ownApiGroups. Write access in a namespace minted after install is granted by the owner of that namespace as it creates it, never pre-granted here." -}}
{{- end -}}
{{- if and (gt (len $mutNs) 0) (not (gt (len $mut) 0)) -}}
{{- fail (printf "pleme-lib.rbac: rbac.mutate.namespaces names %d namespace(s) but rbac.mutate.rules is empty. That renders a Role granting nothing in each — it reads as write access and is not. Declare rbac.mutate.rules, or drop rbac.mutate.namespaces." (len $mutNs)) -}}
{{- end -}}

{{/* readOnly means read-only, wildcards included */}}
{{- if $r.readOnly -}}
{{- if gt (len $mut) 0 -}}
{{- fail "pleme-lib.rbac: rbac.readOnly=true alongside rbac.mutate.rules. Those contradict: set rbac.readOnly=false and say what it writes, or drop rbac.mutate." -}}
{{- end -}}
{{- range $i, $rule := $all -}}
{{- range $v := ($rule.verbs | default list) -}}
{{- if not (has $v $readVerbs) -}}
{{- fail (printf "pleme-lib.rbac: rbac.readOnly=true but rule %d grants verb %q. readOnly emits get/list/watch and nothing else — a read-only claim that can still mutate is worse than no claim, because it is the claim an operator reads instead of reading the verbs. Remove the verb, or set rbac.readOnly=false." $i $v) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* the observe set is the READ set, at every scope */}}
{{- range $i, $rule := $obs -}}
{{- range $v := ($rule.verbs | default list) -}}
{{- if not (has $v $readVerbs) -}}
{{- fail (printf "pleme-lib.rbac: rbac.observe.rules[%d] grants verb %q. observe is placed at the widest reach rbac.scope allows, so a write verb here would be granted at that reach — the exact defect the split exists to prevent. Move it to rbac.mutate.rules and name the namespaces in rbac.mutate.namespaces." $i $v) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* resourceNames is inert for the verbs that have no object name at authz time */}}
{{- $nameless := list "create" "list" "watch" "deletecollection" -}}
{{- range $i, $rule := $all -}}
{{- if gt (len ($rule.resourceNames | default list)) 0 -}}
{{- range $v := ($rule.verbs | default list) -}}
{{- if has $v $nameless -}}
{{- fail (printf "pleme-lib.rbac: rule %d pairs resourceNames with verb %q. Kubernetes cannot scope that verb by name — a create has no object name at authorization time, and list/watch/deletecollection authorize a collection — so the rule reads as a narrow grant and authorizes nothing for %q. Split it: keep resourceNames on the by-name verbs, and declare %q in its own rule without resourceNames so its width is visible." $i $v $v $v) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* guest-cluster: the split needs a declared ownership boundary */}}
{{- if eq $scope "guest-cluster" -}}
{{- $own := $r.ownApiGroups | default list -}}
{{- if not (gt (len $own) 0) -}}
{{- fail "pleme-lib.rbac: rbac.scope=guest-cluster requires rbac.ownApiGroups — the API groups this workload OWNS. guest-cluster works by splitting the rules: owned groups go cluster-wide (the host holds zero objects of those kinds, so the grant reads nothing of theirs, and it is what lets the workload watch namespaces minted after install); everything else is bound to the release namespace alone. Without the list there is no split, and the only remaining choices are a cluster-wide read of the host's data or a workload blind to its own kind." -}}
{{- end -}}
{{- $ownedRules := 0 -}}
{{- range $i, $rule := $simple -}}
{{- $groups := $rule.apiGroups | default list -}}
{{- if not (gt (len $groups) 0) -}}
{{- fail (printf "pleme-lib.rbac: rbac.rules[%d] declares no apiGroups, so rbac.scope=guest-cluster cannot place it. Name the group explicitly — the core group is \"\"." $i) -}}
{{- end -}}
{{- $inOwn := list -}}
{{- $outOwn := list -}}
{{- range $g := $groups -}}
{{- if has $g $own -}}
{{- $inOwn = append $inOwn $g -}}
{{- else -}}
{{- $outOwn = append $outOwn $g -}}
{{- end -}}
{{- end -}}
{{- if and (gt (len $inOwn) 0) (gt (len $outOwn) 0) -}}
{{- fail (printf "pleme-lib.rbac: rbac.rules[%d] mixes owned apiGroups %s with foreign ones %s. Under rbac.scope=guest-cluster a rule is placed by what it can reach, so this one would have to be both cluster-wide and namespaced. Split it into two rules." $i (toJson $inOwn) (toJson $outOwn)) -}}
{{- end -}}
{{- if gt (len $inOwn) 0 -}}
{{- $ownedRules = add1 $ownedRules -}}
{{- end -}}
{{- end -}}
{{- if eq $ownedRules 0 -}}
{{- fail (printf "pleme-lib.rbac: rbac.scope=guest-cluster but no rule in rbac.rules names any of rbac.ownApiGroups %s. Every rule would land in the release namespace — that is rbac.scope=namespaced with extra steps, and the workload could never watch its own kind." (toJson $own)) -}}
{{- end -}}
{{- end -}}

{{/* the pairing law: scope decides what is ALLOWED, the env var what is TRIED */}}
{{/*
`hasKey`, not `default`. An empty list is FALSY in Go templates, so
`$r.namespaceEnvVars | default (list "WATCH_NAMESPACE")` rewrites the caller's
`[]` back into the default and quietly re-arms the check they just switched
off — the same shape as a `default` filter rewriting a deliberate 0. The
opt-out has to be readable as "the key is present", never as "the value is
truthy". Measured here: `namespaceEnvVars: []` failed the render it was
written to permit.
*/}}
{{- $nsVars := list "WATCH_NAMESPACE" -}}
{{- if hasKey $r "namespaceEnvVars" -}}
{{- $nsVars = $r.namespaceEnvVars | default list -}}
{{- end -}}
{{- if gt (len $nsVars) 0 -}}
{{- $envList := ($ctx.Values).env | default list -}}
{{- if hasKey $r "env" -}}
{{- $envList = $r.env | default list -}}
{{- end -}}
{{- $foundName := "" -}}
{{- $restricting := false -}}
{{- range $e := $envList -}}
{{- if has ($e.name | default "" | toString) $nsVars -}}
{{- $foundName = ($e.name | toString) -}}
{{- if or (trim ($e.value | default "" | toString)) ($e.valueFrom) -}}
{{- $restricting = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and (eq $scope "guest-cluster") $restricting -}}
{{- fail (printf "pleme-lib.rbac: rbac.scope=guest-cluster is paired with %s UNSET, but env sets it to a value. guest-cluster grants the owned API groups cluster-wide precisely so the workload can reach namespaces minted after install; a namespace-restricting env var blinds it to exactly those, and the failure is silent — the object is accepted by the apiserver and then never reconciled. Remove the %s entry from env (or leave it empty), or set rbac.scope=namespaced." $foundName $foundName) -}}
{{- end -}}
{{- if and (eq $scope "namespaced") (not $restricting) -}}
{{- fail (printf "pleme-lib.rbac: rbac.scope=namespaced grants only the release namespace, but no namespace-restricting env var is set — the workload will still try to watch cluster-wide and fail on RBAC at runtime, not at render. Set one of %s in env, or declare rbac.namespaceEnvVars: [] if this workload has no such knob." (toJson $nsVars)) -}}
{{- end -}}
{{- end -}}

{{/* the withheld ledger must be readable and must not contradict the rules */}}
{{- $granted := list -}}
{{- range $rule := $all -}}
{{- range $g := ($rule.apiGroups | default list) -}}
{{- range $res := ($rule.resources | default list) -}}
{{- $granted = append $granted (printf "%s/%s" ($g | toString) ($res | toString)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- range $i, $w := ($r.withheld | default list) -}}
{{- if not (trim ($w.reason | default "" | toString)) -}}
{{- fail (printf "pleme-lib.rbac: rbac.withheld[%d] has no `reason`. A withheld grant with no reason is indistinguishable from an oversight, and the next author closes the gap with a green build. State what breaks without it and who would have used it." $i) -}}
{{- end -}}
{{- range $g := ($w.apiGroups | default list) -}}
{{- range $res := ($w.resources | default list) -}}
{{- if has (printf "%s/%s" ($g | toString) ($res | toString)) $granted -}}
{{- fail (printf "pleme-lib.rbac: rbac.withheld[%d] names %q, which this identity's own rules grant. The ledger is what an operator reads to know an absence was a decision; a ledger that contradicts the rules teaches them to stop reading it." $i (printf "%s/%s" ($g | toString) ($res | toString))) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* a name collision with the sibling maps only surfaces at apply time */}}
{{- range $k, $v := (($r.roles) | default dict) -}}
{{- if eq ($k | kebabcase) $name -}}
{{- fail (printf "pleme-lib.rbac: rbac.roles[%q] renders Role/%s, the same name pleme-lib.rbac emits. Rename the map entry — the collision would otherwise surface as a duplicate-resource error at apply time, long after the render." $k $name) -}}
{{- end -}}
{{- end -}}
{{- range $k, $v := (($r.clusterRoles) | default dict) -}}
{{- if eq ($k | kebabcase) $name -}}
{{- fail (printf "pleme-lib.rbac: rbac.clusterRoles[%q] renders ClusterRole/%s, the same name pleme-lib.rbac emits. Rename the map entry." $k $name) -}}
{{- end -}}
{{- end -}}

{{/* an unbounded namespace delete, checked ONLY against the rules THIS scope
     actually places at cluster reach. Runs last on purpose: under
     guest-cluster it reads the owned/foreign split, and the guard above has
     already refused any rule that mixes the two, so asking whether ANY group
     is owned is a complete test of where the rule lands. Under
     scope=namespaced nothing here reaches cluster-wide and the check is
     correctly silent — a Role is bound to one namespace, and one namespace IS
     the bounded namespace list. */}}
{{- $clusterReach := list -}}
{{- if eq $scope "cluster" -}}
{{- $clusterReach = concat $simple $obs -}}
{{- else if eq $scope "guest-cluster" -}}
{{- $ownGroups := $r.ownApiGroups | default list -}}
{{- range $rule := $simple -}}
{{- $owned := false -}}
{{- range $g := ($rule.apiGroups | default list) -}}
{{- if has $g $ownGroups -}}{{- $owned = true -}}{{- end -}}
{{- end -}}
{{- if $owned -}}{{- $clusterReach = append $clusterReach $rule -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- include "pleme-lib.rbac.namespaceDeleteBound" (dict "rules" $clusterReach "where" (printf "rbac.rules (placed at cluster reach by rbac.scope=%s)" $scope)) -}}
{{- end -}}

{{/* ── the emitter ─────────────────────────────────────────────────────── */}}
{{- define "pleme-lib.rbac" -}}
{{- $ctx := .ctx -}}
{{- if not $ctx -}}
{{- fail "pleme-lib.rbac takes ONE dict argument and needs the root context in it: (dict \"ctx\" .). Optional keys: `rbac` (defaults to .Values.rbac) and `name` (defaults to pleme-lib.fullname)." -}}
{{- end -}}
{{- $r := .rbac | default (($ctx.Values).rbac | default dict) -}}
{{- $name := .name | default (include "pleme-lib.fullname" $ctx) -}}
{{- $args := dict "ctx" $ctx "rbac" $r "name" $name -}}
{{/* DEFAULT-OFF, like every sibling template in this directory.

     This was `or (not (hasKey $r "create")) $r.create` — i.e. absence meant
     RENDER — which made the template impossible to `include` unconditionally:
     a chart that wanted no RBAC still had to declare `rbac.create: false` or
     the render FAILED demanding a scope. Found by writing the first test that
     included it with no values at all.

     Default-on is also the wrong direction for this particular template. The
     thing it emits is a grant; the safe absence is no grant. Changed while it
     had ZERO consumers (measured), so nothing depended on the old default. */}}
{{- if $r.create -}}
{{- include "pleme-lib.rbac.validate" $args -}}
{{- $scope := include "pleme-lib.rbac.scope" $args -}}
{{- $ns := include "pleme-lib.namespace" $ctx -}}
{{- $labels := include "pleme-lib.labels" $ctx -}}
{{- $att := include "pleme-lib.attestationAnnotations" $ctx | trim -}}
{{- $ledger := include "pleme-lib.rbac.ledger" (dict "rbac" $r "scope" $scope) | trim -}}
{{- $sa := ($r.serviceAccount) | default dict -}}
{{/*
Name resolution, most specific first: rbac.serviceAccount.name, then the
chart-wide serviceAccount.name, then this identity's own name. It ends at the
identity's own name rather than at pleme-lib.serviceAccountName because that
helper answers "default" for a chart that never declared a ServiceAccount — and
this template is the thing declaring one, so inheriting that answer would bind
the namespace's ambient identity by omission rather than by choice.
*/}}
{{- $saName := $sa.name | default ((($ctx.Values).serviceAccount | default dict).name) | default $name -}}
{{- if eq $saName "default" -}}
{{- fail "pleme-lib.rbac: the ServiceAccount resolved to \"default\". Binding a namespace's default ServiceAccount hands this identity to anything that later lands there. Set rbac.serviceAccount.name, or serviceAccount.create=true." -}}
{{- end -}}
{{- $saCreate := true -}}
{{- if hasKey $sa "create" -}}
{{- $saCreate = $sa.create -}}
{{- end -}}
{{- $simple := $r.rules | default list -}}
{{- $obs := (($r.observe) | default dict).rules | default list -}}
{{- $mut := (($r.mutate) | default dict).rules | default list -}}
{{- $mutNs := (($r.mutate) | default dict).namespaces | default (list $ns) -}}
{{- $own := $r.ownApiGroups | default list -}}
{{- $clusterHalf := list -}}
{{- $localHalf := list -}}
{{- if eq $scope "guest-cluster" -}}
{{- range $rule := $simple -}}
{{- $isOwn := false -}}
{{- range $g := ($rule.apiGroups | default list) -}}
{{- if has $g $own -}}
{{- $isOwn = true -}}
{{- end -}}
{{- end -}}
{{- if $isOwn -}}
{{- $clusterHalf = append $clusterHalf $rule -}}
{{- else -}}
{{- $localHalf = append $localHalf $rule -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if $saCreate }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $saName }}
  namespace: {{ $ns }}
  labels:
    {{- $labels | nindent 4 }}
  {{- with $sa.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- if hasKey $sa "automountServiceAccountToken" }}
automountServiceAccountToken: {{ $sa.automountServiceAccountToken }}
{{- end }}
{{- end }}

{{- if eq $scope "guest-cluster" }}
{{- /* owned kinds reach cluster-wide — the host owns none of them */ -}}
{{- include "pleme-lib.rbac.role" (dict "ctx" $ctx "cluster" true "name" $name "namespace" $ns "rules" $clusterHalf "labels" $labels "att" $att "ledger" $ledger "sa" $saName) }}
{{- if gt (len $localHalf) 0 }}
{{- /* anything that could touch host data — the release namespace, and only it */ -}}
{{- include "pleme-lib.rbac.role" (dict "ctx" $ctx "cluster" false "name" (printf "%s-local" $name) "namespace" $ns "rules" $localHalf "labels" $labels "att" $att "ledger" $ledger "sa" $saName) }}
{{- end }}
{{- else if gt (len $simple) 0 }}
{{- include "pleme-lib.rbac.role" (dict "ctx" $ctx "cluster" (eq $scope "cluster") "name" $name "namespace" $ns "rules" $simple "labels" $labels "att" $att "ledger" $ledger "sa" $saName) }}
{{- else }}
{{- if gt (len $obs) 0 }}
{{- /* OBSERVE — the read set, at the widest reach this scope allows */ -}}
{{- include "pleme-lib.rbac.role" (dict "ctx" $ctx "cluster" (eq $scope "cluster") "name" $name "namespace" $ns "rules" $obs "labels" $labels "att" $att "ledger" $ledger "sa" $saName) }}
{{- end }}
{{- range $target := $mutNs }}
{{- /* MUTATE — a Role in one named namespace, never cluster-scoped, at any scope */ -}}
{{- include "pleme-lib.rbac.role" (dict "ctx" $ctx "cluster" false "name" (printf "%s-write" $name) "namespace" $target "rules" $mut "labels" $labels "att" $att "ledger" $ledger "sa" $saName "saNamespace" $ns) }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
pleme-lib.rbac.role — one (Role|ClusterRole) + its binding. Internal to
pleme-lib.rbac; every placement decision is already made by the caller, so this
emits and never chooses. `saNamespace` differs from `namespace` exactly when a
Role in a target namespace binds a ServiceAccount that lives in ours.
*/}}
{{- define "pleme-lib.rbac.role" -}}
{{/*
The leading newline is emitted HERE, by omitting the right-hand trim on the
line below, so the `---` separator can never be welded onto the previous
document by a caller that trimmed its own trailing newline. That is not
hypothetical: one call site out of four did exactly that, and the result was
a ServiceAccount whose last label line ended `...-platform---`. It renders,
exit 0, and only the document count says anything is wrong.
*/}}
{{- $kind := ternary "ClusterRole" "Role" .cluster }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: {{ $kind }}
metadata:
  name: {{ .name }}
  {{- if not .cluster }}
  namespace: {{ .namespace }}
  {{- end }}
  labels:
    {{- .labels | nindent 4 }}
  {{- if or .att .ledger }}
  annotations:
    {{- with .att }}
    {{- . | nindent 4 }}
    {{- end }}
    {{- with .ledger }}
    {{- . | nindent 4 }}
    {{- end }}
  {{- end }}
rules:
  {{- toYaml .rules | nindent 2 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: {{ $kind }}Binding
metadata:
  name: {{ .name }}
  {{- if not .cluster }}
  namespace: {{ .namespace }}
  {{- end }}
  labels:
    {{- .labels | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: {{ $kind }}
  name: {{ .name }}
subjects:
  - kind: ServiceAccount
    name: {{ .sa }}
    namespace: {{ .saNamespace | default .namespace }}
{{- end -}}
