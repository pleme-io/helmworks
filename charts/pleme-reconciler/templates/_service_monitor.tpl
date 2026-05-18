{{/*
pleme-reconciler.serviceMonitor

Renders a ServiceMonitor selecting the consumer's reconciler pod's
metrics port. Skipped when `reconciler.serviceMonitor.enabled: false`.

Selector contract: the consumer's Service must carry the labels
`magma.pleme.io/reconciler=<kind>` for this ServiceMonitor to find
it. The convention pairs with `Reconciler::kind()` on the Rust side.

Per theory/CONVERGENCE-SUBSTRATE.md §IV.3.
*/}}
{{- define "pleme-reconciler.serviceMonitor" -}}
{{- $sm := .Values.reconciler.serviceMonitor | default dict -}}
{{- if $sm.enabled }}
{{- $kind := .Values.reconciler.kind | default (printf "%s" .Chart.Name) -}}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ printf "%s-reconciler" $kind }}
  labels:
    app.kubernetes.io/name:       {{ .Chart.Name | quote }}
    app.kubernetes.io/component:  reconciler-metrics
    app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
    magma.pleme.io/reconciler:    {{ $kind | quote }}
{{- with $sm.labels }}
{{ toYaml . | indent 4 }}
{{- end }}
spec:
  selector:
    matchLabels:
      magma.pleme.io/reconciler: {{ $kind | quote }}
  endpoints:
    - port: {{ $sm.portName | default "metrics" | quote }}
      path: {{ $sm.path | default "/metrics" | quote }}
      interval: {{ $sm.interval | default "30s" | quote }}
{{- end }}
{{- end }}
