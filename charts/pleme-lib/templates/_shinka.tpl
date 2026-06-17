{{/*
pleme-lib: Shinka database migration templates

Produces:
  1. DatabaseMigration CRD (shinka.pleme.io/v1alpha1)
  2. Wait init container (polls for migration completion before app starts)

The migration body exposes the FULL shinka DatabaseMigration CRD surface
(shinka/src/crd/database_migration.rs): the singular `migrator` AND the ordered
`migrators[]` list (sqlx→seaorm sequential cutover), every MigratorSpec field
(imageOverride / args / workingDir / migrationsPath / toolConfig / secretRefs /
envFrom / containerName), a migrator-type allowlist guard, and metadata
annotations passthrough (the load-bearing shinka.pleme.io/retry +
release.shinka.pleme.io/expected-tag signals). The wait init exposes the full
shinka_wait env surface (SHINKA_URL / CHECK_MODE migration|database / CLUSTER_NAME
/ DATABASE / the two HTTP timeouts / securityContext). All additions are
`{{- with }}`/`default`-gated — a values shape that set only the legacy fields
renders byte-identically.
*/}}

{{/*
pleme-lib.shinka.migratorFields — the MigratorSpec body (no leading indent).
Arg: (dict "m" <migrator-map> "ctx" $root). Used by BOTH the singular `migrator:`
and each `migrators[]` item so the surface is defined once.
*/}}
{{- define "pleme-lib.shinka.migratorFields" -}}
{{- $m := .m -}}
{{- $ctx := .ctx -}}
{{- $type := $m.type | default "sqlx" -}}
{{- $allowed := list "sqlx" "refinery" "diesel" "seaorm" "goose" "golang-migrate" "atlas" "dbmate" "flyway" "liquibase" "custom" -}}
{{- if not (has $type $allowed) -}}
{{- fail (printf "pleme-lib.shinka: migrator type %q is not one of %v" $type $allowed) -}}
{{- end -}}
name: {{ $m.name | default (include "pleme-lib.fullname" $ctx) }}
type: {{ $type }}
{{- with $m.deploymentRef }}
deploymentRef:
  name: {{ .name | default (include "pleme-lib.fullname" $ctx) }}
  {{- with .containerName }}
  containerName: {{ . }}
  {{- end }}
{{- end }}
{{- with $m.imageOverride }}
imageOverride: {{ . }}
{{- end }}
{{- with $m.command }}
command:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.args }}
args:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.workingDir }}
workingDir: {{ . }}
{{- end }}
{{- with $m.migrationsPath }}
migrationsPath: {{ . }}
{{- end }}
{{- with $m.env }}
env:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.toolConfig }}
toolConfig:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.secretRefs }}
secretRefs:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.envFrom }}
envFrom:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.resources }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.serviceAccountName }}
serviceAccountName: {{ . }}
{{- end }}
{{- end -}}

{{/*
pleme-lib.shinkaDatabaseMigration — renders a Shinka DatabaseMigration CR

Gated by .Values.shinkaMigration.enabled
*/}}
{{- define "pleme-lib.shinkaDatabaseMigration" -}}
{{- if (.Values.shinkaMigration).enabled }}
{{- $sm := .Values.shinkaMigration }}
apiVersion: shinka.pleme.io/v1alpha1
kind: DatabaseMigration
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    component: migrations
    job-type: migration
  {{- with $sm.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  database:
    cnpgClusterRef:
      name: {{ $sm.database.cnpgClusterRef.name }}
      {{- with $sm.database.cnpgClusterRef.database }}
      database: {{ . }}
      {{- end }}
  {{- if $sm.migrators }}
  {{- /* Ordered multi-migrator list (e.g. sqlx → seaorm). Wins over singular per the CRD. */}}
  migrators:
  {{- range $sm.migrators }}
    -
      {{- include "pleme-lib.shinka.migratorFields" (dict "m" . "ctx" $) | nindent 6 }}
  {{- end }}
  {{- else }}
  migrator:
    {{- include "pleme-lib.shinka.migratorFields" (dict "m" ($sm.migrator | default dict) "ctx" $) | nindent 4 }}
  {{- end }}
  {{- with $sm.safety }}
  safety:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $sm.timeouts }}
  timeouts:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.shinkaWaitInitContainer — renders an init container that waits for migration completion

Gated by .Values.shinkaWait.enabled. Output is a single list item (- name: ...).
Exposes the full shinka_wait env surface: migration mode (default) gates on the
named DatabaseMigration reaching Ready; database mode (checkMode: database) gates
on the CNPG cluster + all its migrations being ready.
*/}}
{{- define "pleme-lib.shinkaWaitInitContainer" -}}
{{- if (.Values.shinkaWait).enabled }}
{{- $w := .Values.shinkaWait }}
- name: wait-for-migrations
  image: {{ $w.image | default "ghcr.io/pleme-io/shinka:amd64-latest" }}
  env:
    - name: RUN_MODE
      value: "wait"
    - name: CHECK_MODE
      value: {{ $w.checkMode | default "migration" | quote }}
    - name: MIGRATION_NAME
      value: {{ $w.migrationName | default (include "pleme-lib.fullname" .) | quote }}
    - name: MIGRATION_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    {{- with $w.clusterName }}
    - name: CLUSTER_NAME
      value: {{ . | quote }}
    {{- end }}
    {{- with $w.database }}
    - name: DATABASE
      value: {{ . | quote }}
    {{- end }}
    {{- with $w.shinkaUrl }}
    - name: SHINKA_URL
      value: {{ . | quote }}
    {{- end }}
    - name: TIMEOUT_SECONDS
      value: {{ $w.timeoutSeconds | default 300 | quote }}
    - name: RETRY_INTERVAL_SECONDS
      value: {{ $w.retryIntervalSeconds | default 5 | quote }}
    {{- with $w.httpRequestTimeoutSeconds }}
    - name: HTTP_REQUEST_TIMEOUT_SECONDS
      value: {{ . | quote }}
    {{- end }}
    {{- with $w.httpClientTimeoutSeconds }}
    - name: HTTP_CLIENT_TIMEOUT_SECONDS
      value: {{ . | quote }}
    {{- end }}
    - name: LOG_LEVEL
      value: {{ $w.logLevel | default "info" | quote }}
  {{- with $w.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  resources:
    {{- toYaml ($w.resources | default (dict "requests" (dict "cpu" "10m" "memory" "16Mi") "limits" (dict "cpu" "100m" "memory" "32Mi"))) | nindent 4 }}
{{- end }}
{{- end }}
