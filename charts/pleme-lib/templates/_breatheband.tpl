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
*/}}

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
  setpoint: {{ $mem.setpoint | default 0.8 }}
  floor: {{ $mem.floor | default "256Mi" | quote }}
  ceiling: {{ $mem.ceiling | default "2Gi" | quote }}
  growAbove: {{ $mem.growAbove | default 0.85 }}
  growFactor: {{ $mem.growFactor | default 1.25 }}
  shrinkBelow: {{ $mem.shrinkBelow | default 0.7 }}
  shrinkFactor: {{ $mem.shrinkFactor | default 0.9 }}
  cooldownSeconds: {{ $mem.cooldownSeconds | default 600 }}
  disruptionPolicy: {{ $mem.disruptionPolicy | default "allowRestart" }}
  dryRun: {{ $mem.dryRun | default false }}
  {{- with $mem.mode }}
  mode: {{ . }}
  {{- end }}
  maxStalenessSeconds: {{ $mem.maxStalenessSeconds | default 120 }}
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
  setpoint: {{ $cpu.setpoint | default 0.8 }}
  floor: {{ $cpu.floor | default "200m" | quote }}
  ceiling: {{ $cpu.ceiling | default "2000m" | quote }}
  growAbove: {{ $cpu.growAbove | default 0.85 }}
  growFactor: {{ $cpu.growFactor | default 1.25 }}
  shrinkBelow: {{ $cpu.shrinkBelow | default 0.7 }}
  shrinkFactor: {{ $cpu.shrinkFactor | default 0.9 }}
  cooldownSeconds: {{ $cpu.cooldownSeconds | default 600 }}
  disruptionPolicy: {{ $cpu.disruptionPolicy | default "allowRestart" }}
  dryRun: {{ $cpu.dryRun | default false }}
  {{- with $cpu.mode }}
  mode: {{ . }}
  {{- end }}
  maxStalenessSeconds: {{ $cpu.maxStalenessSeconds | default 120 }}
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
  setpoint: {{ $sto.setpoint | default 0.8 }}
  floor: {{ $sto.floor | default "1Gi" | quote }}
  ceiling: {{ $sto.ceiling | default "100Gi" | quote }}
  growAbove: {{ $sto.growAbove | default 0.8 }}
  growFactor: {{ $sto.growFactor | default 1.5 }}
  cooldownSeconds: {{ $sto.cooldownSeconds | default 3600 }}
  disruptionPolicy: {{ $sto.disruptionPolicy | default "allowRestart" }}
  dryRun: {{ $sto.dryRun | default true }}
  {{- with $sto.mode }}
  mode: {{ . }}
  {{- end }}
  maxStalenessSeconds: {{ $sto.maxStalenessSeconds | default 300 }}
{{- end }}
{{- end }}
{{- end }}
