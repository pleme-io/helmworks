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

{{/*
pleme-lib.shinkaClickHouseMigration — renders a Shinka DatabaseMigration CR whose
source is the DatabaseSource::ClickHouse arm (spec.database.clickhouseRef), the
third arm of the DatabaseSpec sum type alongside cnpgClusterRef / directRef.

Unlike pleme-lib.shinkaDatabaseMigration (a CNPG source that runs a migrator Job
off a deployment image), a ClickHouse migration carries NO migrator: the shinka
controller resolves the source through require_clickhouse_ref() (which IS the
health-skip — a ClickHouse source has no CNPG cluster to poll), renders the named
typed `analitico` model server-side, and converges it create-only (ON CLUSTER,
ReplicatedMergeTree). The rendered model is content-addressed into
status.lastMigration.imageTag as chmodel-<hex>. So this template emits
spec.database only — never migrator / migrators.

Dict arg (a typed model + the CH connection + the cluster name):
  ctx           — the root chart context (REQUIRED; for labels/fullname/namespace)
  name          — DatabaseMigration name        (default: ctx fullname)
  namespace     — namespace                      (default: ctx namespace)
  model         — ClickHouseModel enum           (default: events)
  host          — CH HTTP host                   (REQUIRED; e.g. clickhouse.monitoring.svc)
  port          — CH HTTP port                   (optional; CRD effective_port()=8123)
  database      — target database                (REQUIRED; e.g. tendril)
  cluster       — ON CLUSTER distributed-DDL cluster (REQUIRED; e.g. tendril)
  table         — table-name override            (optional; CRD default = model canonical name)
  username      — CH username                    (optional; CRD effective_username()="default")
  secretName    — Secret holding the CH password (REQUIRED)
  passwordKey   — key within secretName          (optional; CRD default "clickhouse-password")
  annotations   — extra metadata annotations     (optional map; e.g. the shinka.pleme.io/retry signal)
*/}}
{{- define "pleme-lib.shinkaClickHouseMigration" -}}
{{- $ctx := .ctx | required "pleme-lib.shinkaClickHouseMigration: .ctx is required" -}}
{{- $host := .host | required "pleme-lib.shinkaClickHouseMigration: .host is required" -}}
{{- $database := .database | required "pleme-lib.shinkaClickHouseMigration: .database is required" -}}
{{- $cluster := .cluster | required "pleme-lib.shinkaClickHouseMigration: .cluster is required" -}}
{{- $secretName := .secretName | required "pleme-lib.shinkaClickHouseMigration: .secretName is required" -}}
apiVersion: shinka.pleme.io/v1alpha1
kind: DatabaseMigration
metadata:
  name: {{ .name | default (include "pleme-lib.fullname" $ctx) }}
  namespace: {{ .namespace | default (include "pleme-lib.namespace" $ctx) }}
  labels:
    {{- include "pleme-lib.labels" $ctx | nindent 4 }}
    component: migrations
    job-type: migration
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  database:
    clickhouseRef:
      model: {{ .model | default "events" }}
      host: {{ $host | quote }}
      {{- with .port }}
      port: {{ . }}
      {{- end }}
      database: {{ $database | quote }}
      cluster: {{ $cluster | quote }}
      {{- with .table }}
      table: {{ . | quote }}
      {{- end }}
      {{- with .username }}
      username: {{ . | quote }}
      {{- end }}
      credentialsSecretRef:
        name: {{ $secretName | quote }}
      passwordKey: {{ .passwordKey | default "clickhouse-password" | quote }}
{{- end -}}
