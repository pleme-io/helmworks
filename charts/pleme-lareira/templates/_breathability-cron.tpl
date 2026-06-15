{{/*
pleme-lareira.breathability.cron — KEDA cron-trigger ScaledObject for
"sleep overnight, wake during the day" home services.

pleme-lib's _breathability.tpl ships NATS-JetStream-driven scale-to-zero
which is right for queue workers. For homelab workloads, the more useful
trigger is the cron type — wake at 07:00, sleep at 23:00, save the
memory overnight.

Activate via:

  breathability:
    enabled: true            # parent toggle (also unlocks pleme-lib's NATS path)
    cron:
      enabled: true
      timezone: America/New_York
      start: "0 7 * * *"
      end: "0 23 * * *"
      desiredReplicas: 1

This ScaledObject scales the Deployment from 0 → desiredReplicas during
the active window. Outside the window, KEDA scales to 0 after the
cooldown.

Use in consumer chart templates/breathability.yaml:

  {{- if include "pleme-lareira.enabled" . }}
  {{- include "pleme-lareira.breathability.cron" . }}
  {{- end }}

If both pleme-lib's NATS-driven breathability AND this cron-driven one
are enabled simultaneously, KEDA picks the higher of the trigger
verdicts — i.e., a queue with messages overrides the sleep window.
*/}}

{{- define "pleme-lareira.breathability.cron" -}}
{{- if and (.Values.breathability).enabled ((.Values.breathability).cron).enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ $fullname }}-cron
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    pleme.io/breathability-trigger: cron
spec:
  scaleTargetRef:
    kind: Deployment
    name: {{ $fullname }}
  minReplicaCount: 0
  maxReplicaCount: {{ .Values.breathability.cron.desiredReplicas | int }}
  cooldownPeriod: 300
  pollingInterval: 30
  triggers:
    - type: cron
      metadata:
        timezone: {{ .Values.breathability.cron.timezone | quote }}
        start: {{ .Values.breathability.cron.start | quote }}
        end: {{ .Values.breathability.cron.end | quote }}
        desiredReplicas: {{ .Values.breathability.cron.desiredReplicas | quote }}
{{- end }}
{{- end -}}
