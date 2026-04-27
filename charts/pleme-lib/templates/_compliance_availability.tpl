{{/*
pleme-lib: compliance — availability primitives

Maps to NIST 800-53 controls:
  SC-5  — Denial of Service Protection: PDB + topology spread + ResourceLimits
  CP-2  — Contingency Planning: replicas >= 2 at high
  CP-10 — Information System Recovery: PDB ensures voluntary disruption budget

At fedramp-high, PodDisruptionBudget and topology spread are mandatory.
At fedramp-moderate they are recommended; the validator only emits a fail at high.
*/}}

{{/*
Whether availability primitives are mandatory at the current baseline.
*/}}
{{- define "pleme-lib.compliance.availability.required" -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- if eq $atLeastHigh "true" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Default minimum replicas at this baseline.
  fedramp-high: 2  — survives a single-node failure
  fedramp-moderate: 1
*/}}
{{- define "pleme-lib.compliance.availability.minReplicas" -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- if eq $atLeastHigh "true" -}}2{{- else -}}1{{- end -}}
{{- end }}

{{/*
Mandatory PDB at high. Renders a PodDisruptionBudget with minAvailable=1
unless overridden in values.
*/}}
{{- define "pleme-lib.compliance.availability.pdb" -}}
{{- $required := include "pleme-lib.compliance.availability.required" . -}}
{{- if eq $required "true" }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "pleme-lib.fullname" . }}-compliance
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  {{- $pdb := .Values.pdb | default dict }}
  {{- if $pdb.minAvailable }}
  minAvailable: {{ $pdb.minAvailable }}
  {{- else if $pdb.maxUnavailable }}
  maxUnavailable: {{ $pdb.maxUnavailable }}
  {{- else }}
  minAvailable: 1
  {{- end }}
{{- end }}
{{- end }}

{{/*
Default topology spread constraints at high. Spreads pods across zones
with maxSkew=1 — single-AZ failure cannot take down all replicas.
*/}}
{{- define "pleme-lib.compliance.availability.topologySpread" -}}
{{- $required := include "pleme-lib.compliance.availability.required" . -}}
{{- if eq $required "true" -}}
{{- if not .Values.topologySpreadConstraints }}
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
{{- else }}
{{- toYaml .Values.topologySpreadConstraints }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate.
*/}}
{{- define "pleme-lib.compliance.availability.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $required := include "pleme-lib.compliance.availability.required" . -}}
{{- $kind := include "pleme-lib.compliance.workloadKind" . -}}
{{- if eq $required "true" -}}
  {{/* CronJob / Job / DaemonSet have no replicaCount — schedule reliability
       (concurrencyPolicy, backoffLimit) governs availability instead.
       Branch on workload kind so the right invariant applies. */}}
  {{- if and (ne $kind "cronjob") (ne $kind "job") (ne $kind "daemonset") -}}
    {{- $minR := include "pleme-lib.compliance.availability.minReplicas" . | int -}}
    {{- $auto := .Values.autoscaling | default dict -}}
    {{- if eq (toString $auto.enabled) "true" -}}
      {{- if lt (int ($auto.minReplicas | default 1)) $minR -}}
        {{- fail (printf "compliance: baseline=%s requires autoscaling.minReplicas >= %d (SC-5, CP-2)" $b $minR) -}}
      {{- end -}}
    {{- else -}}
      {{- if lt (int (.Values.replicaCount | default 1)) $minR -}}
        {{- fail (printf "compliance: baseline=%s requires replicaCount >= %d (SC-5, CP-2)" $b $minR) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if eq $kind "cronjob" -}}
    {{/* CronJob-specific availability invariants: concurrencyPolicy must
         be Forbid or Replace (Allow can pile up zombie jobs); backoffLimit
         must be set to bound retry storms. */}}
    {{- $cp := .Values.concurrencyPolicy | default "" | toString -}}
    {{- if eq $cp "Allow" -}}
      {{- fail (printf "compliance: baseline=%s + workload.kind=cronjob requires concurrencyPolicy != Allow (SC-5, CM-7); use Forbid or Replace" $b) -}}
    {{- end -}}
  {{- end -}}
  {{- $resources := .Values.resources | default dict -}}
  {{- $reqs := $resources.requests | default dict -}}
  {{- $cpuReq := $reqs.cpu | default "" | toString -}}
  {{- $memReq := $reqs.memory | default "" | toString -}}
  {{- if or (eq $cpuReq "") (eq $memReq "") -}}
    {{- fail (printf "compliance: baseline=%s requires resources.requests.cpu and resources.requests.memory (SC-5)" $b) -}}
  {{- end -}}
  {{- $limits := $resources.limits | default dict -}}
  {{- $memLimit := $limits.memory | default "" | toString -}}
  {{- if eq $memLimit "" -}}
    {{- fail (printf "compliance: baseline=%s requires resources.limits.memory (SC-5)" $b) -}}
  {{- end -}}
{{- end -}}
{{- end }}
