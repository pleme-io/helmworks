{{/*
Required-clusterName check. Used at the top of every render-emitting
template so disabled charts or missing values fail fast at lint time
rather than silently producing zero output.
*/}}
{{- define "pleme-cnpg-cluster.requireClusterName" -}}
{{- if not .Values.clusterName -}}
{{- fail "pleme-cnpg-cluster: .Values.clusterName is required" -}}
{{- end -}}
{{- end -}}

{{/*
Required-bootstrap check. database + owner + secretName must all be
set together; missing any of them is a fail-loud at install time.
*/}}
{{- define "pleme-cnpg-cluster.requireBootstrap" -}}
{{- if not .Values.bootstrap.database -}}
{{- fail "pleme-cnpg-cluster: .Values.bootstrap.database is required" -}}
{{- end -}}
{{- if not .Values.bootstrap.owner -}}
{{- fail "pleme-cnpg-cluster: .Values.bootstrap.owner is required" -}}
{{- end -}}
{{- if not .Values.bootstrap.secretName -}}
{{- fail "pleme-cnpg-cluster: .Values.bootstrap.secretName is required (Secret with username+password keys for the owner)" -}}
{{- end -}}
{{- end -}}

{{/*
Render postInitSQL with the magic `__OWNER__` placeholder substituted
for the actual owner name. Lets the values.yaml carry a reusable
default without baking in a specific owner.
*/}}
{{- define "pleme-cnpg-cluster.postInitSQL" -}}
{{- range .Values.bootstrap.postInitSQL -}}
{{- $sql := . | replace "__OWNER__" $.Values.bootstrap.owner -}}
- {{ $sql | quote }}
{{ end }}
{{- end -}}

{{/*
Common Helm + chart-author labels. Renders the standard k8s
managed-by/instance/name set so kubectl + helm tooling can find the
resources, plus a fleet-wide `pleme.io/cnpg-cluster` for filtering.
The user-provided `clusterLabels` are stamped on top via
toYaml-merge in each template.
*/}}
{{- define "pleme-cnpg-cluster.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/name: pleme-cnpg-cluster
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
pleme.io/cnpg-cluster: {{ .Values.clusterName }}
{{- end -}}
