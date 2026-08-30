{{/*
pleme-lib: compliance — the STORAGE POSTURE (ephemeral | durable).

★ THIS IS THE `pleme-lib.compliance.storage.*` FAMILY, CONTINUED — not a new
one. It lives in its own file only because `_compliance_storage.tpl` is the
encrypted-storage-class validator and this is a second, orthogonal question
about the same surface; the compliance layer is already split across ~25
`_compliance_*.tpl` files for exactly that reason. Every define below is
`pleme-lib.compliance.storage.<x>`, and `pleme-lib.compliance.storage.validate`
calls into it, so there is ONE storage validator entry point, not two.

── WHY A POSTURE EXISTS AT ALL ──────────────────────────────────────────────
An ephemeral environment should be memory-backed. Not for speed — the reason is
that a drive is where UNDECLARED STATE HIDES. A pod that can write to a disk
that outlives it accumulates facts nobody declared: a migration that ran once, a
cache warmed by hand, a file someone scp'd in at 2am. Take the disk away and the
declaration becomes the only source of truth, because it is the only thing left
that can put a byte on the substrate. That is the whole argument, and it is an
argument about EVIDENCE, not performance.

── AND WHY IT IS NOT THE DEFAULT ────────────────────────────────────────────
The argument holds only while storage is INCIDENTAL to what is under test. When
storage BEHAVIOUR is the thing under test, a ramdisk is incoherent:

  * A restore rehearsal on tmpfs rehearses nothing. You cannot practise
    recovering from a failure mode the substrate cannot produce — no partial
    write, no torn page, no volume that detaches mid-flush.
  * A soak measuring IO on tmpfs measures the page cache. tmpfs is unthrottled,
    so an IO regression is INVISIBLE: the number that would have moved is not
    being produced by a device.
  * And the failure shape inverts. A full disk is ENOSPC — attributable, at the
    write, in the workload's own logs. A full memory-backed emptyDir is an
    OOMKill of the whole pod, attributed to the container, at a moment unrelated
    to the write that caused it.

So `posture` DEFAULTS TO `durable`. Absent is not a request: a chart that has
never heard of this file gets exactly the behaviour it had before, and the
ephemeral posture is something an author opts into for one environment.

── WHAT `ephemeral` REFUSES ─────────────────────────────────────────────────
Under `posture: ephemeral` the render FAILS on any of:

  1. `persistence.enabled: true`              — the chart would emit a PVC
  2. a non-empty `volumeClaimTemplates`       — the StatefulSet would emit N
  3. a `volumes[]` entry referencing a PVC    — same class as 1 and 2: a claim
                                                reaching the pod, by reference
  4. an `emptyDir` without `medium: Memory`   — a node-disk-backed scratch dir
                                                is the disk, wearing a name
                                                that sounds like it is not
  5. a memory-backed `emptyDir` with no       — see the OOMKill note above:
     `sizeLimit`                                unbounded trades a disk-full you
                                                can attribute for a kill you
                                                cannot
  6. a `durability` declaration above `none`  — see the next section

Refusals 1–3 are one class (durable claims) split three ways because a claim can
reach a pod by three different values keys and each one has to be named at the
point of failure to be actionable.

── DURABILITY: THE DECLARATION THE POSTURE CONTRADICTS ──────────────────────
`compliance.storage.durability` is a chart AUTHOR's statement about what the
workload needs, in a closed set of three:

  none           — nothing survives the pod. The default.
  outlivesPod    — state must survive a restart or a reschedule.
  snapshottable  — state must additionally be capturable and restorable.

It is deliberately three words and one guard, not a type system. Its only job is
to catch the combination that is a contradiction rather than a configuration
mistake: a chart whose author has said "this needs state to outlive the pod"
cannot also be run on a substrate that has no state that outlives the pod. That
disagreement is between two DECLARATIONS, so it is caught by reading them
against each other — there is no value to inspect and no cluster to ask.

── THE EMITTER ──────────────────────────────────────────────────────────────
`compliance.storage.ephemeral.volumes` is a list of `{name, sizeLimit}` from
which `ephemeral.volumes` renders the pod volumes and `ephemeral.memoryCeiling`
renders their summed contribution to the pod's memory limit. They read the SAME
list, so the ceiling cannot drift from the sizes — which is the failure this
emitter exists to prevent. A memory-backed emptyDir is charged to the pod's
memory cgroup, so a chart that declares 3 × 2Gi of tmpfs and a 2Gi memory limit
is one full scratch directory away from an OOMKill, and nothing in the manifest
says so. Hand-maintaining the sum is how that happens.
*/}}

{{/*
The active posture. One of "ephemeral" | "durable"; anything else fails.

A closed set with a `fail` on the unrecognised arm rather than a silent fallback
to the default: `posture: ephmeral` must not read as `durable` and quietly grant
the workload a disk.
*/}}
{{- define "pleme-lib.compliance.storage.posture" -}}
{{- $cs := ((.Values.compliance) | default dict).storage | default dict -}}
{{- $p := $cs.posture | default "durable" | toString | lower | trim -}}
{{- if not (has $p (list "ephemeral" "durable")) -}}
{{- fail (printf "storage-posture: compliance.storage.posture=%q is not a posture; the closed set is [durable ephemeral] and the default is durable" $p) -}}
{{- end -}}
{{- $p -}}
{{- end }}

{{/*
The declared durability need. One of "none" | "outlivesPod" | "snapshottable".
Closed for the same reason `posture` is: a typo here would otherwise read as
"needs nothing", which is the permissive direction.
*/}}
{{- define "pleme-lib.compliance.storage.durability" -}}
{{- $cs := ((.Values.compliance) | default dict).storage | default dict -}}
{{- $d := $cs.durability | default "none" | toString | trim -}}
{{- if not (has $d (list "none" "outlivesPod" "snapshottable")) -}}
{{- fail (printf "storage-posture: compliance.storage.durability=%q is not a durability; the closed set is [none outlivesPod snapshottable] and the default is none" $d) -}}
{{- end -}}
{{- $d -}}
{{- end }}

{{/*
Parse a Kubernetes quantity to bytes. Args: (list <quantity> <valuesKeyForError>).

Fractional quantities ("1.5Gi") are REFUSED rather than rounded. K8s accepts
them; this emitter does not, because its whole purpose is that the ceiling is
the exact sum of the sizes, and a rounded summand makes the ceiling a number
nobody can reproduce by adding up the manifest. The error names the key and the
fix, so the cost of the refusal is one edit.
*/}}
{{- define "pleme-lib.compliance.storage.quantityBytes" -}}
{{- $q := (index . 0) | toString | trim -}}
{{- $where := (index . 1) | toString -}}
{{- $num := regexFind "^[0-9]+" $q -}}
{{- $suf := $q | trimPrefix $num -}}
{{- $mult := dict "" 1 "Ki" 1024 "Mi" 1048576 "Gi" 1073741824 "Ti" 1099511627776 "k" 1000 "K" 1000 "M" 1000000 "G" 1000000000 "T" 1000000000000 -}}
{{- if contains "." $q -}}
{{- fail (printf "storage-posture: %s=%q is not an integer quantity; write it as 512Mi / 2Gi (a fractional quantity is refused so the memory ceiling stays the exact sum of the sizes)" $where $q) -}}
{{- end -}}
{{- if eq $num "" -}}
{{- fail (printf "storage-posture: %s=%q has no leading integer and is not a quantity at all; write it as 512Mi / 2Gi" $where $q) -}}
{{- end -}}
{{- if not (hasKey $mult $suf) -}}
{{- fail (printf "storage-posture: %s=%q carries the unrecognised unit %q; use one of [Ki Mi Gi Ti k K M G T] or a bare byte count" $where $q $suf) -}}
{{- end -}}
{{- mul (atoi $num) (index $mult $suf) -}}
{{- end }}

{{/*
The declared ephemeral scratch volumes, normalised. Internal — the two public
surfaces below both fold over this so they cannot disagree about the set.
Each entry must carry `name` and `sizeLimit`; a missing one fails naming the
index, because a nameless volume is not attachable and an unbounded one is the
OOMKill this whole file is about.
*/}}
{{- define "pleme-lib.compliance.storage.ephemeral.declared" -}}
{{- $cs := ((.Values.compliance) | default dict).storage | default dict -}}
{{- $e := $cs.ephemeral | default dict -}}
{{- $out := list -}}
{{- range $i, $v := ($e.volumes | default list) -}}
  {{- $name := ($v.name | default "" | toString) -}}
  {{- if eq $name "" -}}
    {{- fail (printf "storage-posture: compliance.storage.ephemeral.volumes[%d].name is required — a volume with no name cannot be mounted" $i) -}}
  {{- end -}}
  {{- $size := ($v.sizeLimit | default "" | toString) -}}
  {{- if eq $size "" -}}
    {{- fail (printf "storage-posture: compliance.storage.ephemeral.volumes[%d] (name=%s) has no sizeLimit — an unbounded memory-backed emptyDir trades a disk-full you can attribute for an OOMKill you cannot" $i $name) -}}
  {{- end -}}
  {{- $out = append $out (dict "name" $name "sizeLimit" $size) -}}
{{- end -}}
{{- $out | toJson -}}
{{- end }}

{{/*
EMITTER — the pod `volumes:` fragment for the declared scratch set.

Renders a bare YAML list, so a consumer splices it with `nindent`:

    volumes:
      {{- include "pleme-lib.compliance.storage.ephemeral.volumes" . | nindent 8 }}

Every emitted volume is memory-backed and bounded BY CONSTRUCTION, which is why
the posture guard below only inspects hand-authored `.Values.volumes`: a volume
that came through here has no shape in which it could violate the guard. Making
the compliant form the easy one is the point — the guard is the backstop for
volumes written by hand, not the mechanism.

Emits under either posture. The declaration `compliance.storage.ephemeral.*` is
already explicit about what it wants; a durable chart is free to keep a bounded
memory scratch dir, and refusing that here would only push the author back to a
hand-written emptyDir with no sizeLimit.
*/}}
{{- define "pleme-lib.compliance.storage.ephemeral.volumes" -}}
{{- $decl := include "pleme-lib.compliance.storage.ephemeral.declared" . | fromJsonArray -}}
{{- range $decl }}
- name: {{ .name }}
  emptyDir:
    medium: Memory
    sizeLimit: {{ .sizeLimit }}
{{- end }}
{{- end }}

{{/*
EMITTER — the summed memory-ceiling contribution of the declared scratch set,
rendered as a Mi quantity (rounded UP to the next whole Mi, never down: a
ceiling that undercounts is worse than no ceiling).

    resources:
      limits:
        memory: {{ include "pleme-lib.compliance.storage.ephemeral.memoryCeiling" . }}   # + the process's own

Reads the same declaration as the volume emitter, so the number and the sizes
move together. An empty declaration yields `0Mi` — which is also the DENOMINATOR
for anything asserting on this value: a discovery path that broke and found
nothing renders 0Mi, not the expected total, so the assertion goes red instead of
silently agreeing with an empty set.
*/}}
{{- define "pleme-lib.compliance.storage.ephemeral.memoryCeiling" -}}
{{- $decl := include "pleme-lib.compliance.storage.ephemeral.declared" . | fromJsonArray -}}
{{- $total := 0 -}}
{{- range $decl -}}
  {{- $where := printf "compliance.storage.ephemeral.volumes[%s].sizeLimit" .name -}}
  {{- $total = add $total (include "pleme-lib.compliance.storage.quantityBytes" (list .sizeLimit $where) | int64) -}}
{{- end -}}
{{- printf "%dMi" (div (add $total 1048575) 1048576) -}}
{{- end }}

{{/*
THE GUARD. Called from `pleme-lib.compliance.storage.validate` and directly from
the workload templates, so it runs whether or not a compliance overlay is on —
the posture is an environment-shape decision, not a FedRAMP control, and gating
it behind `compliance.enforce` would leave it dead for every chart that has no
baseline selected (which is most of them).

Renders nothing under `posture: durable`, which is the default, which is why no
existing chart changes behaviour by upgrading pleme-lib.
*/}}
{{- define "pleme-lib.compliance.storage.posture.validate" -}}
{{- $posture := include "pleme-lib.compliance.storage.posture" . -}}
{{- $durability := include "pleme-lib.compliance.storage.durability" . -}}
{{- if eq $posture "ephemeral" -}}

  {{- /* [6] Two declarations that contradict each other. Checked first because
         it is the one that means the AUTHOR is wrong about the environment,
         rather than a value being wrong within it — reporting a sizeLimit nit
         first would send the reader to fix the wrong thing. */ -}}
  {{- if ne $durability "none" -}}
    {{- fail (printf "storage-posture: compliance.storage.durability=%s cannot combine with compliance.storage.posture=ephemeral — this chart has declared that its state must outlive the pod, and an ephemeral posture is a substrate on which no state does; pick one" $durability) -}}
  {{- end -}}

  {{- /* [1] The chart's own PVC. */ -}}
  {{- $persistence := .Values.persistence | default dict -}}
  {{- if eq (toString $persistence.enabled) "true" -}}
    {{- fail "storage-posture: persistence.enabled=true cannot combine with compliance.storage.posture=ephemeral — it emits a PersistentVolumeClaim, and a claim is exactly the place undeclared state hides; set persistence.enabled=false or compliance.storage.posture=durable" -}}
  {{- end -}}

  {{- /* [2] The StatefulSet's per-replica claims. A separate check from [1]
         because `volumeClaimTemplates` is a FIELD on the StatefulSet, not a
         document — nothing that looks for a PVC document ever sees it. */ -}}
  {{- $vcts := .Values.volumeClaimTemplates | default list -}}
  {{- if gt (len $vcts) 0 -}}
    {{- fail (printf "storage-posture: volumeClaimTemplates has %d entry/entries and cannot combine with compliance.storage.posture=ephemeral — each one is a per-replica PersistentVolumeClaim; move the scratch data to compliance.storage.ephemeral.volumes or set compliance.storage.posture=durable" (len $vcts)) -}}
  {{- end -}}

  {{- range $i, $v := (.Values.volumes | default list) -}}
    {{- $vname := ($v.name | default (printf "#%d" $i)) -}}

    {{- /* [3] A claim reaching the pod by reference rather than by emission. */ -}}
    {{- if $v.persistentVolumeClaim -}}
      {{- fail (printf "storage-posture: volumes[%d] (%s) references a PersistentVolumeClaim and cannot combine with compliance.storage.posture=ephemeral — a claim mounted by reference is the same durable state as one this chart emitted" $i $vname) -}}
    {{- end -}}

    {{- /* hasKey, NOT `if $v.emptyDir`: an `emptyDir: {}` is an EMPTY MAP, which is
           FALSY in Go templates — and `emptyDir: {}` is precisely the node-disk-backed
           scratch dir this refusal exists for, so the truthiness form skipped the one
           case that mattered. (It did, until it went red here.) */ -}}
    {{- if hasKey $v "emptyDir" -}}
      {{- $ed := $v.emptyDir | default dict -}}
      {{- $medium := ($ed.medium | default "" | toString) -}}

      {{- /* [4] A disk wearing a name that sounds like it is not one. An
             emptyDir with no medium is backed by the NODE's disk, and it is
             the single easiest way to reintroduce hidden state under a
             posture that claims to have removed it. */ -}}
      {{- if ne $medium "Memory" -}}
        {{- fail (printf "storage-posture: volumes[%d].emptyDir (%s) has medium=%q and cannot combine with compliance.storage.posture=ephemeral — an emptyDir without medium=Memory is backed by the node's disk; set volumes[%d].emptyDir.medium=Memory" $i $vname $medium $i) -}}
      {{- end -}}

      {{- /* [5] Bounded, or the failure shape inverts from an attributable
             ENOSPC at the write into an OOMKill of the whole pod at an
             unrelated moment. */ -}}
      {{- if not (hasKey $ed "sizeLimit") -}}
        {{- fail (printf "storage-posture: volumes[%d].emptyDir (%s) is memory-backed with no sizeLimit and cannot combine with compliance.storage.posture=ephemeral — unbounded tmpfs trades a disk-full you can attribute for an OOMKill you cannot; set volumes[%d].emptyDir.sizeLimit, or declare it via compliance.storage.ephemeral.volumes so the size and the memory ceiling stay one number" $i $vname $i) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

{{- end -}}
{{- end }}
