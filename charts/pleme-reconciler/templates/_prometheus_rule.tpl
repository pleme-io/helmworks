{{/*
pleme-reconciler.prometheusRule

Renders typed drift-severity alert rules. Three alerts per
reconciler kind:

  * <Kind>DriftCritical    → severity=critical, page
  * <Kind>DriftFunctional  → severity=warning, ticket
  * <Kind>DriftCosmetic    → severity=info,    log

Routing: the `severity` Prometheus label maps to Alertmanager
routes per pleme-io's standard route tree. Consumers can override
the routing → label mapping via
`reconciler.prometheusRule.severityRouting.<level>`.

Metric assumed: `magma_drift_classified_total{kind, severity}` —
emitted by magma-drift's typed K8s-events-and-metrics adapter (the
operator-side wiring lands alongside).

Per theory/CONVERGENCE-SUBSTRATE.md §IV.1 + IV.3.
*/}}
{{- define "pleme-reconciler.prometheusRule" -}}
{{- $pr := .Values.reconciler.prometheusRule | default dict -}}
{{- if $pr.enabled }}
{{- $kind := .Values.reconciler.kind | default (printf "%s" .Chart.Name) -}}
{{- $title := $kind | replace "_" "" | title -}}
{{- $routing  := $pr.severityRouting | default (dict "critical" "page" "functional" "ticket" "cosmetic" "log") -}}
{{- $duration := $pr.durations       | default (dict "critical" "1m" "functional" "10m" "cosmetic" "1h") -}}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ printf "%s-reconciler-drift" $kind }}
  labels:
    app.kubernetes.io/name:       {{ .Chart.Name | quote }}
    app.kubernetes.io/component:  reconciler-alerts
    app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
    magma.pleme.io/reconciler:    {{ $kind | quote }}
spec:
  groups:
    - name: {{ printf "%s.drift" $kind }}
      rules:
        - alert: {{ printf "%sDriftCritical" $title }}
          expr: |
            sum by (kind) (
              increase(magma_drift_classified_total{kind="{{ $kind }}", severity="critical"}[5m])
            ) > 0
          for: {{ index $duration "critical" | quote }}
          labels:
            severity: critical
            magma_drift_severity: critical
            routing: {{ index $routing "critical" | quote }}
            reconciler: {{ $kind | quote }}
          annotations:
            summary:     "Critical drift on {{ $kind }} reconciler"
            description: "magma-drift classified one or more changes as Critical severity on the {{ $kind }} reconciler in the last 5 minutes. Holding for approval per conservative policy."
        - alert: {{ printf "%sDriftFunctional" $title }}
          expr: |
            sum by (kind) (
              increase(magma_drift_classified_total{kind="{{ $kind }}", severity="functional"}[10m])
            ) > 0
          for: {{ index $duration "functional" | quote }}
          labels:
            severity: warning
            magma_drift_severity: functional
            routing: {{ index $routing "functional" | quote }}
            reconciler: {{ $kind | quote }}
          annotations:
            summary:     "Functional drift on {{ $kind }} reconciler"
            description: "magma-drift classified one or more changes as Functional severity on the {{ $kind }} reconciler in the last 10 minutes. Auto-corrected with alert per conservative policy."
        - alert: {{ printf "%sDriftCosmetic" $title }}
          expr: |
            sum by (kind) (
              increase(magma_drift_classified_total{kind="{{ $kind }}", severity="cosmetic"}[1h])
            ) > 0
          for: {{ index $duration "cosmetic" | quote }}
          labels:
            severity: info
            magma_drift_severity: cosmetic
            routing: {{ index $routing "cosmetic" | quote }}
            reconciler: {{ $kind | quote }}
          annotations:
            summary:     "Cosmetic drift on {{ $kind }} reconciler"
            description: "magma-drift classified cosmetic changes on the {{ $kind }} reconciler over the last hour. Auto-corrected silently per conservative policy."
{{- end }}
{{- end }}
