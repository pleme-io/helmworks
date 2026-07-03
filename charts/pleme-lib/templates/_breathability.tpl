{{/*
pleme-lib.breathability — unified elastic architecture template.

Renders KEDA ScaledObject (zero-scale workers) and/or HPA (elastic serving),
giving any chart "breathable" behavior with a standard values block.

Architecture:
  NATS queue → KEDA (0→N workers) → process → target (HPA 1→M)
  When idle: workers=0, target=min. Cost approaches zero.

Usage in a chart's templates/breathability.yaml:
  {{- include "pleme-lib.breathability" . }}

Values:
  breathability:
    enabled: true
    targetKind: Deployment      # or StatefulSet
    targetName: ""              # defaults to fullname
    min: 0                      # 0 = true zero-scale
    max: 4
    cooldown: 300               # seconds idle → scale to zero
    pollingInterval: 15
    trigger:
      type: nats-jetstream      # trigger type (extensible)
      nats:
        serverURL: "nats://nats.nats.svc:4222"
        stream: BUILD
        consumer: builder
        lagThreshold: "1"
        activationLagThreshold: "0"
    hpa:
      enabled: false
      min: 1
      max: 3
      targetCPU: 70
      scaleUp:
        stabilization: 60
        pods: 1
        period: 60
      scaleDown:
        stabilization: 300
        pods: 1
        period: 120
*/}}

{{- define "pleme-lib.breathability" -}}
{{- $g := .Values.global | default dict }}
{{- $b := .Values.breathability | default $g.breathability | default dict }}
{{- if $b.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $targetName := default $fullname $b.targetName }}
{{- $targetKind := default "Deployment" $b.targetKind }}

{{/* ── KEDA ScaledObject (zero-scale workers) ─────────────────────── */}}
{{- if and $b.trigger (eq (default "nats-jetstream" $b.trigger.type) "nats-jetstream") }}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    kind: {{ $targetKind }}
    name: {{ $targetName }}
  minReplicaCount: {{ default 0 $b.min }}
  maxReplicaCount: {{ default 4 $b.max }}
  cooldownPeriod: {{ default 300 $b.cooldown }}
  pollingInterval: {{ default 15 $b.pollingInterval }}
  triggers:
    - type: nats-jetstream
      metadata:
        natsServerMonitoringEndpoint: {{ $b.trigger.nats.serverURL | replace "nats://" "" | replace ":4222" ":8222" | quote }}
        # KEDA's nats-jetstream scaler requires the NATS account; the default
        # no-auth global account is "$G". Configurable for accounted setups.
        account: {{ default "$G" $b.trigger.nats.account | quote }}
        stream: {{ $b.trigger.nats.stream | quote }}
        consumer: {{ $b.trigger.nats.consumer | quote }}
        lagThreshold: {{ default "1" $b.trigger.nats.lagThreshold | quote }}
        activationLagThreshold: {{ default "0" $b.trigger.nats.activationLagThreshold | quote }}
{{- end }}

{{/* ── HPA (elastic serving targets) ─────────────────────────────── */}}
{{- if $b.hpa }}
{{- if $b.hpa.enabled }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ $targetKind }}
    name: {{ $targetName }}
  minReplicas: {{ default 1 $b.hpa.min }}
  maxReplicas: {{ default 3 $b.hpa.max }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ default 70 $b.hpa.targetCPU }}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: {{ default 60 (($b.hpa).scaleUp).stabilization }}
      policies:
        - type: Pods
          value: {{ default 1 (($b.hpa).scaleUp).pods }}
          periodSeconds: {{ default 60 (($b.hpa).scaleUp).period }}
    scaleDown:
      stabilizationWindowSeconds: {{ default 300 (($b.hpa).scaleDown).stabilization }}
      policies:
        - type: Pods
          value: {{ default 1 (($b.hpa).scaleDown).pods }}
          periodSeconds: {{ default 120 (($b.hpa).scaleDown).period }}
{{- end }}
{{- end }}

{{- end }}
{{- end }}
