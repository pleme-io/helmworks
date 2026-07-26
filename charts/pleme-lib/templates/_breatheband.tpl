{{/*
pleme-lib: breatheBand named template — the breathe.pleme.io homeostasis primitive.

Emits ZERO..THREE documents from a `.Values.breathe` block:
  - a breathe.pleme.io/v1 MemoryBand  (when breathe.memory.enabled, default true)
  - a breathe.pleme.io/v1 CpuBand     (when breathe.cpu.enabled,    default false)
  - a breathe.pleme.io/v1 StorageBand (when breathe.storage.enabled + a pvcName;
    GROW-ONLY — carves a PVC's spec.resources.requests.storage, EBS online-expand)

A *band* is a NAMESPACED CR. The breathe controller carves
`resources.limits.{memory,cpu}` on the band's targetRef workload to hold that
workload's utilization at the band's `setpoint` — the band center. Default
setpoint is 0.8 (the 80/20 law). MemoryBand floor/ceiling are memory quantities
(e.g. 256Mi / 2Gi); CpuBand floor/ceiling are CPU quantities in millicores
(e.g. 200m / 2000m).

Dual-mode targetRef (load-bearing):
  - INLINE  — `.Values.breathe.targetRef` is EMPTY ⇒ the band targets the
              chart's OWN workload: { apiVersion: apps/v1, kind: Deployment,
              name: <pleme-lib.fullname> }. Inline charts band their own deploy.
  - EXTERNAL — `.Values.breathe.targetRef.name` is set ⇒ the band targets that
              explicit workload. lareira-observe passes an explicit external
              targetRef here (see CONTRACT in values.yaml).

The CR name is "<target>-memory" / "<target>-cpu", where <target> is the
explicit targetRef name when given, else <pleme-lib.fullname>.

Usage in a chart's templates/breatheband.yaml:
  {{- include "pleme-lib.breatheBand" . }}

Every spec field the band controller reads is settable; `default` filters keep
a minimal values block (just breathe.enabled + breathe.memory.setpoint)
rendering a valid CR.

── postureRef (2026-07-26) ─────────────────────────────────────────────
`breathe.<dim>.postureRef` (or `breathe.postureRef` for all three dims)
names a cluster-scoped BreathePosture that supplies the TUNING tuple
(setpoint / growAbove / growFactor / shrinkBelow / shrinkFactor /
cooldownSeconds / disruptionPolicy / maxStalenessSeconds).

WHY THIS IS A TEMPLATE CHANGE AND NOT A VALUES CHANGE -- the load-bearing
detail, do not "simplify" this away: breathe resolves each tuning field as
`inline.or(posture).or(compiled_default)`, PER FIELD
(breathe-crd/src/lib.rs `band_config_with_posture`, pinned by its own test
`explicit_override_always_wins_over_posture`). Those spec fields are
`Option<T>` with `skip_serializing_if`, and the CRD declares no defaults --
so the controller genuinely distinguishes "absent" from "explicitly 0.8".

Before this change the template emitted the full tuple UNCONDITIONALLY from
its own hardcoded defaults. Every rendered band therefore carried an
explicit `setpoint: 0.8` etc. on disk, which means a `postureRef` added
alongside it would have been resolved LAST and silently done NOTHING. The
posture only bites when the inline key is genuinely absent -- hence the
`hasKey` gate below, which omits a tuning field exactly when (a) a posture
is named and (b) the chart's values did not explicitly set it.

Precedence, as rendered:
  explicit values.yaml key  >  named posture  >  this template's default
Unchanged when no postureRef is set: every field renders exactly as before,
so this is a purely additive capability for existing consumers.

NOT posture-governed, deliberately: floor / ceiling / requestFloor are plain
(non-Option) fields the CRD always materializes and a BreathePosture
structurally cannot carry -- they stay per-band. Likewise `dryRun` and
`mode`.

── dryRun is DEAD CODE for these band kinds -- read before trusting it ──
`spec.dryRun` is INERT on MemoryBand/CpuBand/StorageBand. The band trait's
`promotion_mode()` is `mode_spec().unwrap_or(ShadowConfirmEffect)` and never
consults `dry_run()` (only HostParamBand/KubeParamBand still do). A band
left at the default therefore SHADOW-CONFIRMS-THEN-CARVES LIVE, no matter
what `dryRun` says. `dryRun: true` reads as safety while doing nothing --
it is retained only for wire-compatibility.

The ONLY lever that actually withholds a carve is `mode`:
  shadow             -- never carves (short-circuits before the confirm gate)
  suspended          -- never carves
  shadowConfirmEffect-- DEFAULT: auto-promotes to live after the confirm window
  effect             -- carves immediately
A BreathePosture cannot carry `mode`, so a postureRef alone NEVER stops a
band from carving -- it only retunes how hard it carves. Set `mode: shadow`
for that.
*/}}

{{/*
pleme-lib.breatheBand.tuning — emit the posture-governed tuning fields.

Takes { cfg, posture, fields } where `fields` is an ORDERED list of
{ k: <spec key>, d: <template default> }. Order is explicit (not a dict
range) so rendered output stays stable and reviewable.

Emission rule, per field:
  - values.yaml set it explicitly  -> emit the explicit value (wins over posture)
  - no posture named               -> emit this template's default (legacy behavior)
  - posture named, key absent      -> emit NOTHING, so the posture supplies it

`hasKey` rather than `default` is load-bearing: `default` would rewrite a
legitimate falsy value, and the never-shrink postures use exactly that --
`shrinkBelow: 0` would silently become 0.7 under a `default` filter.
*/}}
{{- define "pleme-lib.breatheBand.tuning" -}}
{{- $cfg := .cfg -}}
{{- $posture := .posture -}}
{{- range $t := .fields }}
{{- if hasKey $cfg $t.k }}
{{ $t.k }}: {{ index $cfg $t.k }}
{{- else if not $posture }}
{{ $t.k }}: {{ $t.d }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "pleme-lib.breatheBand" -}}
{{- $g := .Values.global | default dict -}}
{{- $breathe := .Values.breathe | default $g.breathe | default dict -}}
{{- if $breathe.enabled }}
{{- $explicit := $breathe.targetRef | default dict -}}
{{- /* Resolve the target workload name: explicit targetRef.name, else fullname. */ -}}
{{- $fullname := include "pleme-lib.fullname" . -}}
{{- $targetName := $explicit.name | default $fullname -}}
{{- /* Resolve the targetRef object: explicit (apiVersion/kind/name), else the
       chart's own apps/v1 Deployment. */ -}}
{{- $targetRef := dict
      "apiVersion" ($explicit.apiVersion | default "apps/v1")
      "kind"       ($explicit.kind       | default "Deployment")
      "name"       $targetName -}}
{{- $labels := include "pleme-lib.labels" . -}}
{{- $namespace := include "pleme-lib.namespace" . -}}
{{/* ── MemoryBand ──────────────────────────────────────────────── */}}
{{- $mem := $breathe.memory | default dict -}}
{{- /* memory band defaults ON; only an explicit `enabled: false` turns it off.
       `default true` can't distinguish unset from false, so check the key. */ -}}
{{- $memEnabled := true -}}
{{- if hasKey $mem "enabled" -}}{{- $memEnabled = $mem.enabled -}}{{- end -}}
{{- if $memEnabled }}
---
apiVersion: breathe.pleme.io/v1
kind: MemoryBand
metadata:
  name: {{ $targetName }}-memory
  namespace: {{ $namespace }}
  labels:
    {{- $labels | nindent 4 }}
spec:
  targetRef:
    apiVersion: {{ $targetRef.apiVersion }}
    kind: {{ $targetRef.kind }}
    name: {{ $targetRef.name }}
  {{- $memPosture := $mem.postureRef | default $breathe.postureRef | default "" }}
  {{- with $memPosture }}
  postureRef: {{ . }}
  {{- end }}
  floor: {{ $mem.floor | default "256Mi" | quote }}
  ceiling: {{ $mem.ceiling | default "2Gi" | quote }}
  {{- with $mem.requestFloor }}
  requestFloor: {{ . | quote }}
  {{- end }}
  {{- $memTuning := include "pleme-lib.breatheBand.tuning" (dict "cfg" $mem "posture" $memPosture "fields" (list
        (dict "k" "setpoint"            "d" 0.8)
        (dict "k" "growAbove"           "d" 0.85)
        (dict "k" "growFactor"          "d" 1.25)
        (dict "k" "shrinkBelow"         "d" 0.7)
        (dict "k" "shrinkFactor"        "d" 0.9)
        (dict "k" "cooldownSeconds"     "d" 600)
        (dict "k" "disruptionPolicy"    "d" "allowRestart")
        (dict "k" "maxStalenessSeconds" "d" 120)
      )) | trim }}
  {{- with $memTuning }}
  {{- . | nindent 2 }}
  {{- end }}
  dryRun: {{ $mem.dryRun | default false }}
  {{- with $mem.mode }}
  mode: {{ . }}
  {{- end }}
{{- end }}
{{/* ── CpuBand ─────────────────────────────────────────────────── */}}
{{- $cpu := $breathe.cpu | default dict -}}
{{- /* cpu band defaults OFF (M2Typed); only an explicit `enabled: true`
       turns it on. Key-check keeps this symmetric with the memory band. */ -}}
{{- $cpuEnabled := false -}}
{{- if hasKey $cpu "enabled" -}}{{- $cpuEnabled = $cpu.enabled -}}{{- end -}}
{{- if $cpuEnabled }}
---
apiVersion: breathe.pleme.io/v1
kind: CpuBand
metadata:
  name: {{ $targetName }}-cpu
  namespace: {{ $namespace }}
  labels:
    {{- $labels | nindent 4 }}
spec:
  targetRef:
    apiVersion: {{ $targetRef.apiVersion }}
    kind: {{ $targetRef.kind }}
    name: {{ $targetRef.name }}
  {{- $cpuPosture := $cpu.postureRef | default $breathe.postureRef | default "" }}
  {{- with $cpuPosture }}
  postureRef: {{ . }}
  {{- end }}
  floor: {{ $cpu.floor | default "200m" | quote }}
  ceiling: {{ $cpu.ceiling | default "2000m" | quote }}
  {{- with $cpu.requestFloor }}
  requestFloor: {{ . | quote }}
  {{- end }}
  {{- $cpuTuning := include "pleme-lib.breatheBand.tuning" (dict "cfg" $cpu "posture" $cpuPosture "fields" (list
        (dict "k" "setpoint"            "d" 0.8)
        (dict "k" "growAbove"           "d" 0.85)
        (dict "k" "growFactor"          "d" 1.25)
        (dict "k" "shrinkBelow"         "d" 0.7)
        (dict "k" "shrinkFactor"        "d" 0.9)
        (dict "k" "cooldownSeconds"     "d" 600)
        (dict "k" "disruptionPolicy"    "d" "allowRestart")
        (dict "k" "maxStalenessSeconds" "d" 120)
      )) | trim }}
  {{- with $cpuTuning }}
  {{- . | nindent 2 }}
  {{- end }}
  dryRun: {{ $cpu.dryRun | default false }}
  {{- with $cpu.mode }}
  mode: {{ . }}
  {{- end }}
{{- end }}
{{/* ── StorageBand ─────────────────────────────────────────────── */}}
{{- $sto := $breathe.storage | default dict -}}
{{- /* storage band defaults OFF (M2Typed); only an explicit `enabled: true`
       turns it on. Unlike memory/cpu the StorageBand targets a PVC, not the
       chart's workload — so it renders ONLY when a pvcName is given (there is
       no fullname default for a PVC). GROW-ONLY: the descriptor clamps shrink,
       so only floor/ceiling/grow* are load-bearing. */ -}}
{{- $stoEnabled := false -}}
{{- if hasKey $sto "enabled" -}}{{- $stoEnabled = $sto.enabled -}}{{- end -}}
{{- $stoPvc := $sto.pvcName | default (($sto.targetRef | default dict).name) | default "" -}}
{{- if and $stoEnabled $stoPvc }}
---
apiVersion: breathe.pleme.io/v1
kind: StorageBand
metadata:
  name: {{ $stoPvc }}-storage
  namespace: {{ $namespace }}
  labels:
    {{- $labels | nindent 4 }}
spec:
  targetRef:
    apiVersion: {{ ($sto.targetRef | default dict).apiVersion | default "v1" }}
    kind: {{ ($sto.targetRef | default dict).kind | default "PersistentVolumeClaim" }}
    name: {{ $stoPvc }}
  {{- $stoPosture := $sto.postureRef | default $breathe.postureRef | default "" }}
  {{- with $stoPosture }}
  postureRef: {{ . }}
  {{- end }}
  floor: {{ $sto.floor | default "1Gi" | quote }}
  ceiling: {{ $sto.ceiling | default "100Gi" | quote }}
  {{- /* Grow-only: the descriptor clamps shrink, so shrinkBelow/shrinkFactor
         are deliberately absent here even when a posture carries them. */}}
  {{- $stoTuning := include "pleme-lib.breatheBand.tuning" (dict "cfg" $sto "posture" $stoPosture "fields" (list
        (dict "k" "setpoint"            "d" 0.8)
        (dict "k" "growAbove"           "d" 0.8)
        (dict "k" "growFactor"          "d" 1.5)
        (dict "k" "cooldownSeconds"     "d" 3600)
        (dict "k" "disruptionPolicy"    "d" "allowRestart")
        (dict "k" "maxStalenessSeconds" "d" 300)
      )) | trim }}
  {{- with $stoTuning }}
  {{- . | nindent 2 }}
  {{- end }}
  dryRun: {{ $sto.dryRun | default true }}
  {{- with $sto.mode }}
  mode: {{ . }}
  {{- end }}
{{- end }}
{{/* ── RequestBand ─────────────────────────────────────────────────────────

     The RESERVATION dimension: carves `resources.requests.<r>`, the field that
     sets `oom_score_adj` and the QoS class. Every other band above carves a
     LIMIT — a limit bounds blast radius, but it is not what decides whether the
     kernel picks you. (Receipt: sui-cache-pg took 34 OOMKills at a 202.8Mi
     high-water against a 1Gi limit with cgroup failcnt=0. No MemoryBand setting
     at any value could have saved it.)

     THREE deliberate departures from the bands above, each a safety property:

     1. DEFAULTS OFF, and when on, defaults to `mode: shadow`. Every other band
        here defaults its GATE off via `dryRun`, which breathe RETIRED — it is
        inert for 8 of 10 kinds and decides nothing. `mode` is the gate that is
        actually read, so this band sets the one that works rather than the one
        that reads reassuringly.
     2. NO `dryRun` key is emitted at all. Emitting an inert field that looks
        like a safety gate is worse than emitting nothing: it invites an
        operator to believe a band is held when it is not.
     3. `resource` is REQUIRED with no default. Guessing between the OOM lever
        (memory) and the scheduling lever (cpu) is exactly the ambiguity this
        dimension exists to remove.

     `manifestRef` is what makes a converged value survive a rollout — the
     in-place resize mutates the POD, not the template, so without it the
     reservation (and therefore the QoS posture) evaporates on the next deploy.
     It is optional here because a band may legitimately be observe-only; when
     absent, breathe reports `Blocked(noManifestCoordinate)` rather than
     silently downgrading to ephemeral. */}}
{{- $req := $breathe.request | default dict -}}
{{- $reqEnabled := false -}}
{{- if hasKey $req "enabled" -}}{{- $reqEnabled = $req.enabled -}}{{- end -}}
{{- $reqResource := $req.resource | default "" -}}
{{- if and $reqEnabled $reqResource }}
---
apiVersion: breathe.pleme.io/v1
kind: RequestBand
metadata:
  name: {{ $targetName }}-request-{{ $reqResource }}
  namespace: {{ $namespace }}
  labels:
    {{- $labels | nindent 4 }}
spec:
  targetRef:
    apiVersion: {{ $targetRef.apiVersion }}
    kind: {{ $targetRef.kind }}
    name: {{ $targetRef.name }}
    {{- with $req.container }}
    container: {{ . }}
    {{- end }}
  resource: {{ $reqResource }}
  {{- $reqPosture := $req.postureRef | default $breathe.postureRef | default "" }}
  {{- with $reqPosture }}
  postureRef: {{ . }}
  {{- end }}
  {{- with $req.workloadClass }}
  workloadClass: {{ . }}
  {{- end }}
  {{- with $req.qosTarget }}
  qosTarget: {{ . }}
  {{- end }}
  {{- with $req.demand }}
  demand:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  durability: {{ $req.durability | default "committed" }}
  {{- with $req.manifestRef }}
  manifestRef:
    path: {{ .path | quote }}
    marker: {{ .marker | quote }}
  {{- end }}
  {{- with $req.floor }}
  floor: {{ . | quote }}
  {{- end }}
  {{- with $req.ceiling }}
  ceiling: {{ . | quote }}
  {{- end }}
  {{- $reqTuning := include "pleme-lib.breatheBand.tuning" (dict "cfg" $req "posture" $reqPosture "fields" (list
        (dict "k" "cooldownSeconds"     "d" 600)
        (dict "k" "disruptionPolicy"    "d" "restartFreeOnly")
        (dict "k" "maxStalenessSeconds" "d" 120)
      )) | trim }}
  {{- with $reqTuning }}
  {{- . | nindent 2 }}
  {{- end }}
  {{- /* Shadow unless the author says otherwise, out loud. */}}
  mode: {{ $req.mode | default "shadow" }}
{{- end }}
{{- end }}
{{- end }}
