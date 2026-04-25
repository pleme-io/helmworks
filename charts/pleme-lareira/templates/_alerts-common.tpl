{{/*
pleme-lareira.alerts.common — baseline PrometheusRule groups for any
home-services workload.

Alerts emitted (when .Values.alerts.common.enabled is true):

  - PodDown:                Deployment has zero ready pods for >N minutes
  - PodRestarting:          Pod restart count > threshold in last hour
  - PodOOMKilled:            kube_pod_container_status_last_terminated_reason="OOMKilled"
  - PvcUsedHigh:             kubelet_volume_stats_used_bytes / capacity_bytes > N%
  - ResticBackupStale:       no successful backup CronJob in 36h (when backup enabled)
  - ResticBackupFailing:     CronJob has failed >2 times in last 24h (when backup enabled)

Each alert carries:
  severity: <.Values.alerts.common.severity>
  ntfy-topic: <.Values.alerts.ntfyTopic>
  chart: <chart-name>
  release: <release-name>

Routing to ntfy is handled by the cluster's Alertmanager config (separate
infra chart). Alertmanager keys off the `ntfy-topic` label.

Use in consumer chart templates/prometheusrule.yaml:

  {{- if include "pleme-lareira.enabled" . }}
  {{- include "pleme-lareira.alerts.common" . }}
  {{- end }}

Or merge with consumer-specific rules:

  {{- $common := include "pleme-lareira.alerts.commonGroups" . | fromYamlArray }}
  {{- $custom := list (dict "name" "myapp" "rules" (list ...)) }}
  ...
*/}}

{{- define "pleme-lareira.alerts.common" -}}
{{- if and .Values.alerts.common.enabled .Values.prometheusRules.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $name := include "pleme-lib.name" . }}
{{- $namespace := include "pleme-lib.namespace" . }}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ $fullname }}-common
  namespace: {{ $namespace }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    pleme.io/alert-set: common
spec:
  groups:
    - name: {{ $name }}.workload
      interval: 1m
      rules:
        - alert: PodDown
          expr: |
            kube_deployment_status_replicas_available{namespace="{{ $namespace }}", deployment="{{ $fullname }}"} == 0
          for: {{ printf "%dm" (int .Values.alerts.common.podDownForMinutes) }}
          labels:
            severity: {{ .Values.alerts.common.severity | quote }}
            chart: {{ $name | quote }}
            release: {{ .Release.Name | quote }}
            {{- with .Values.alerts.ntfyTopic }}
            ntfy-topic: {{ . | quote }}
            {{- end }}
          annotations:
            summary: "{{ $name }} pod has been unavailable"
            description: |
              Deployment {{ $namespace }}/{{ $fullname }} has had zero ready pods for
              more than {{ .Values.alerts.common.podDownForMinutes }} minutes.
        - alert: PodRestarting
          expr: |
            increase(kube_pod_container_status_restarts_total{namespace="{{ $namespace }}", pod=~"{{ $fullname }}-.*"}[1h])
            > {{ .Values.alerts.common.restartsLastHourThreshold }}
          for: 5m
          labels:
            severity: {{ .Values.alerts.common.severity | quote }}
            chart: {{ $name | quote }}
            release: {{ .Release.Name | quote }}
            {{- with .Values.alerts.ntfyTopic }}
            ntfy-topic: {{ . | quote }}
            {{- end }}
          annotations:
            summary: "{{ $name }} pod is restarting frequently"
            description: |
              Pod {{ $fullname }} restarted more than
              {{ .Values.alerts.common.restartsLastHourThreshold }} times in the last hour.
        - alert: PodOOMKilled
          expr: |
            kube_pod_container_status_last_terminated_reason{namespace="{{ $namespace }}", pod=~"{{ $fullname }}-.*", reason="OOMKilled"} > 0
          for: 1m
          labels:
            severity: critical
            chart: {{ $name | quote }}
            release: {{ .Release.Name | quote }}
            {{- with .Values.alerts.ntfyTopic }}
            ntfy-topic: {{ . | quote }}
            {{- end }}
          annotations:
            summary: "{{ $name }} pod was OOMKilled"
            description: |
              A pod for {{ $fullname }} was terminated by the OOM killer. Bump
              .Values.resources.limits.memory or investigate a leak.
{{- if .Values.persistence.enabled }}
    - name: {{ $name }}.storage
      interval: 5m
      rules:
        - alert: PvcUsedHigh
          expr: |
            (
              kubelet_volume_stats_used_bytes{namespace="{{ $namespace }}", persistentvolumeclaim="{{ $fullname }}"}
              /
              kubelet_volume_stats_capacity_bytes{namespace="{{ $namespace }}", persistentvolumeclaim="{{ $fullname }}"}
            ) * 100 > {{ .Values.alerts.common.pvcUsedPercentThreshold }}
          for: 15m
          labels:
            severity: {{ .Values.alerts.common.severity | quote }}
            chart: {{ $name | quote }}
            release: {{ .Release.Name | quote }}
            zfs-dataset: {{ .Values.persistence.zfsDataset | quote }}
            {{- with .Values.alerts.ntfyTopic }}
            ntfy-topic: {{ . | quote }}
            {{- end }}
          annotations:
            summary: "{{ $name }} PVC is filling up"
            description: |
              PVC {{ $fullname }} is more than {{ .Values.alerts.common.pvcUsedPercentThreshold }}% full
              (ZFS dataset {{ .Values.persistence.zfsDataset }}).
{{- end }}
{{- if .Values.backup.enabled }}
    - name: {{ $name }}.backup
      interval: 5m
      rules:
        - alert: ResticBackupStale
          expr: |
            time() - kube_cronjob_status_last_successful_time{namespace="{{ $namespace }}", cronjob="{{ $fullname }}-backup"} > 36 * 3600
          for: 30m
          labels:
            severity: critical
            chart: {{ $name | quote }}
            release: {{ .Release.Name | quote }}
            {{- with .Values.alerts.ntfyTopic }}
            ntfy-topic: {{ . | quote }}
            {{- end }}
          annotations:
            summary: "{{ $name }} backup is stale"
            description: |
              Restic backup CronJob {{ $fullname }}-backup has not succeeded in
              over 36 hours. Investigate.
        - alert: ResticBackupFailing
          expr: |
            increase(kube_job_failed{namespace="{{ $namespace }}", job_name=~"{{ $fullname }}-backup-.*"}[24h]) > 2
          for: 15m
          labels:
            severity: critical
            chart: {{ $name | quote }}
            release: {{ .Release.Name | quote }}
            {{- with .Values.alerts.ntfyTopic }}
            ntfy-topic: {{ . | quote }}
            {{- end }}
          annotations:
            summary: "{{ $name }} backup is failing"
            description: |
              Restic backup for {{ $fullname }} has failed more than 2 times in
              the last 24 hours.
{{- end }}
{{- end }}
{{- end -}}
