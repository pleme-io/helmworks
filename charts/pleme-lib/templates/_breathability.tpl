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
{{- if .Values.breathability }}
{{- if .Values.breathability.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $targetName := default $fullname .Values.breathability.targetName }}
{{- $targetKind := default "Deployment" .Values.breathability.targetKind }}

{{/* ── KEDA ScaledObject (zero-scale workers) ─────────────────────── */}}
{{- if and .Values.breathability.trigger (eq (default "nats-jetstream" .Values.breathability.trigger.type) "nats-jetstream") }}
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
  minReplicaCount: {{ default 0 .Values.breathability.min }}
  maxReplicaCount: {{ default 4 .Values.breathability.max }}
  cooldownPeriod: {{ default 300 .Values.breathability.cooldown }}
  pollingInterval: {{ default 15 .Values.breathability.pollingInterval }}
  triggers:
    - type: nats-jetstream
      metadata:
        natsServerMonitoringEndpoint: {{ .Values.breathability.trigger.nats.serverURL | replace "nats://" "" | replace ":4222" ":8222" | quote }}
        stream: {{ .Values.breathability.trigger.nats.stream | quote }}
        consumer: {{ .Values.breathability.trigger.nats.consumer | quote }}
        lagThreshold: {{ default "1" .Values.breathability.trigger.nats.lagThreshold | quote }}
        activationLagThreshold: {{ default "0" .Values.breathability.trigger.nats.activationLagThreshold | quote }}
{{- end }}

{{/* ── HPA (elastic serving targets) ─────────────────────────────── */}}
{{- if .Values.breathability.hpa }}
{{- if .Values.breathability.hpa.enabled }}
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
  minReplicas: {{ default 1 .Values.breathability.hpa.min }}
  maxReplicas: {{ default 3 .Values.breathability.hpa.max }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ default 70 .Values.breathability.hpa.targetCPU }}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: {{ default 60 ((.Values.breathability.hpa).scaleUp).stabilization }}
      policies:
        - type: Pods
          value: {{ default 1 ((.Values.breathability.hpa).scaleUp).pods }}
          periodSeconds: {{ default 60 ((.Values.breathability.hpa).scaleUp).period }}
    scaleDown:
      stabilizationWindowSeconds: {{ default 300 ((.Values.breathability.hpa).scaleDown).stabilization }}
      policies:
        - type: Pods
          value: {{ default 1 ((.Values.breathability.hpa).scaleDown).pods }}
          periodSeconds: {{ default 120 ((.Values.breathability.hpa).scaleDown).period }}
{{- end }}
{{- end }}

{{- end }}
{{- end }}
{{- end }}
