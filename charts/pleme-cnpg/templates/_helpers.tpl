{{/*
Required-clusterName check. Used at the top of every render-emitting
template so disabled charts or missing values fail fast at lint time.
*/}}
{{- define "pleme-cnpg.requireClusterName" -}}
{{- if not .Values.clusterName -}}
{{- fail "pleme-cnpg: .Values.clusterName is required" -}}
{{- end -}}
{{- end -}}

{{/*
Bootstrap-mode validation. Either initdb or recovery; if you want
neither (i.e. join an existing replication group), unset enabled.
The mode-specific sub-helpers do their own field checks.
*/}}
{{- define "pleme-cnpg.requireBootstrapMode" -}}
{{- $m := .Values.bootstrap.mode -}}
{{- if not (or (eq $m "initdb") (eq $m "recovery")) -}}
{{- fail (printf "pleme-cnpg: .Values.bootstrap.mode must be 'initdb' or 'recovery' (got: %q)" $m) -}}
{{- end -}}
{{- end -}}

{{/*
Required initdb fields. Only checked when mode=initdb.
*/}}
{{- define "pleme-cnpg.requireInitdb" -}}
{{- if eq .Values.bootstrap.mode "initdb" -}}
{{- if not .Values.bootstrap.initdb.database -}}
{{- fail "pleme-cnpg: .Values.bootstrap.initdb.database is required when mode=initdb" -}}
{{- end -}}
{{- if not .Values.bootstrap.initdb.owner -}}
{{- fail "pleme-cnpg: .Values.bootstrap.initdb.owner is required when mode=initdb" -}}
{{- end -}}
{{- if not .Values.bootstrap.initdb.secretName -}}
{{- fail "pleme-cnpg: .Values.bootstrap.initdb.secretName is required when mode=initdb (Secret with username+password keys)" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Recovery-mode serverName resolution. Defaults to clusterName (== bucket
subdir is keyed by the source cluster's name) but consumers commonly
override when restoring into a sibling cluster name.
*/}}
{{- define "pleme-cnpg.recoveryServerName" -}}
{{- default .Values.clusterName .Values.bootstrap.recovery.externalServerName -}}
{{- end -}}

{{/*
Common labels stamped onto every resource. clusterLabels values are
merged on top via toYaml in each template.
*/}}
{{- define "pleme-cnpg.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/name: pleme-cnpg
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
pleme.io/cnpg-cluster: {{ .Values.clusterName }}
{{- end -}}
