{{/*
pleme-lib: Shinka database migration templates

Produces:
  1. DatabaseMigration CRD (shinka.pleme.io/v1alpha1)
  2. Wait init container (polls for migration completion before app starts)
*/}}

{{/*
pleme-lib.shinkaDatabaseMigration — renders a Shinka DatabaseMigration CR

Gated by .Values.shinkaMigration.enabled
*/}}
{{- define "pleme-lib.shinkaDatabaseMigration" -}}
{{- if (.Values.shinkaMigration).enabled }}
apiVersion: shinka.pleme.io/v1alpha1
kind: DatabaseMigration
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    component: migrations
    job-type: migration
spec:
  database:
    cnpgClusterRef:
      name: {{ .Values.shinkaMigration.database.cnpgClusterRef.name }}
      database: {{ .Values.shinkaMigration.database.cnpgClusterRef.database }}

  migrator:
    name: {{ .Values.shinkaMigration.migrator.name | default (include "pleme-lib.fullname" .) }}
    type: {{ .Values.shinkaMigration.migrator.type | default "sqlx" }}
    {{- with .Values.shinkaMigration.migrator.deploymentRef }}
    deploymentRef:
      name: {{ .name | default (include "pleme-lib.fullname" $) }}
    {{- end }}
    {{- with .Values.shinkaMigration.migrator.command }}
    command:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.shinkaMigration.migrator.env }}
    env:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.shinkaMigration.migrator.envFrom }}
    envFrom:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.shinkaMigration.migrator.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.shinkaMigration.migrator.serviceAccountName }}
    serviceAccountName: {{ . }}
    {{- end }}

  {{- with .Values.shinkaMigration.safety }}
  safety:
    {{- toYaml . | nindent 4 }}
  {{- end }}

  {{- with .Values.shinkaMigration.timeouts }}
  timeouts:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.shinkaWaitInitContainer — renders an init container that waits for migration completion

Gated by .Values.shinkaWait.enabled. Output is a single list item (- name: ...).
*/}}
{{- define "pleme-lib.shinkaWaitInitContainer" -}}
{{- if (.Values.shinkaWait).enabled }}
- name: wait-for-migrations
  image: {{ .Values.shinkaWait.image | default "ghcr.io/pleme-io/shinka:amd64-latest" }}
  env:
    - name: RUN_MODE
      value: "wait"
    - name: MIGRATION_NAME
      value: {{ .Values.shinkaWait.migrationName | default (include "pleme-lib.fullname" .) | quote }}
    - name: MIGRATION_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: TIMEOUT_SECONDS
      value: {{ .Values.shinkaWait.timeoutSeconds | default 300 | quote }}
    - name: RETRY_INTERVAL_SECONDS
      value: {{ .Values.shinkaWait.retryIntervalSeconds | default 5 | quote }}
    - name: LOG_LEVEL
      value: {{ .Values.shinkaWait.logLevel | default "info" | quote }}
  resources:
    {{- toYaml (.Values.shinkaWait.resources | default (dict "requests" (dict "cpu" "10m" "memory" "16Mi") "limits" (dict "cpu" "100m" "memory" "32Mi"))) | nindent 4 }}
{{- end }}
{{- end }}
