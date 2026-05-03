{{/*
Required-clusterName check: fail-loud if the consumer didn't set it.
Used at the top of every render-emitting template.
*/}}
{{- define "pleme-cnpg-restore.requireClusterName" -}}
{{- if not .Values.clusterName -}}
{{- fail "pleme-cnpg-restore: .Values.clusterName is required (the new restored cluster's name)" -}}
{{- end -}}
{{- end -}}

{{/*
Effective serverName for the externalCluster. Defaults to the source
cluster name (== bucket subdir). The convention is `clusterName` without
the `-restored`/`-recovery` suffix when restoring into a sibling cluster.
Falls back to clusterName when no explicit override is set.
*/}}
{{- define "pleme-cnpg-restore.serverName" -}}
{{- default .Values.clusterName .Values.recovery.externalServerName -}}
{{- end -}}

{{/*
Common labels applied to every resource the chart emits. Pleme-fleet
convention: identify the recovery operation with a stable label so
humans can grep `kubectl get all -A -l pleme.io/role=cnpg-restore`.
*/}}
{{- define "pleme-cnpg-restore.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/name: pleme-cnpg-restore
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
pleme.io/role: cnpg-restore
pleme.io/cnpg-cluster: {{ .Values.clusterName }}
{{- end -}}
