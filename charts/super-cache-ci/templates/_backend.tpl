{{/*
super-cache-ci: the sui_cache::BackendConfig JSON border.

Builds the tiered BackendConfig as a Helm DICT from `.Values.store.*` and
renders it via `toJson` — a typed serializer, never string concatenation of
JSON syntax (the Helm analog of the ★★ TYPED EMISSION rule: emit a value tree,
serialize it; do not `printf` the braces).

The shape mirrors sui-cache/src/config.rs BackendConfig exactly
(#[serde(tag="type", rename_all="lowercase")]):

  { "type":"tiered",
    "l1": {"type":"redis","url":"redis://redis.super-cache-ci.svc:6379"},
    "l2": {"type":"pg","url":"postgres://sui@postgres.super-cache-ci.svc:5432/sui","max_conns":8},
    "l3": {"type":"s3"|"local"...},
    "write_policy":"write-through" }

This ONE helper is the single source of truth for the tiered config: the serve
daemon's SUI_CACHE_BACKEND_CONFIG (via the ConfigMap that includes this) and
the DNS the consumers dial derive from the same `store.*` values, so the served
tier and the advertised endpoints can never drift.
*/}}

{{- define "super-cache-ci.redisUrl" -}}
{{- printf "redis://%s:%v" .Values.store.redisHost .Values.store.redisPort -}}
{{- end -}}

{{- define "super-cache-ci.postgresUrl" -}}
{{- printf "postgres://%s@%s:%v/%s" .Values.store.postgresUser .Values.store.postgresHost .Values.store.postgresPort .Values.store.postgresDb -}}
{{- end -}}

{{/*
Build the BackendConfig value tree and emit it as compact JSON.
*/}}
{{- define "super-cache-ci.backendConfigJson" -}}
{{- $s := .Values.store -}}
{{/* L1 — Redis */}}
{{- $l1 := dict "type" "redis" "url" (include "super-cache-ci.redisUrl" .) -}}
{{- if and (hasKey $s "redisTtlSecs") (ne (toString $s.redisTtlSecs) "") -}}
{{- $_ := set $l1 "ttl_secs" (int $s.redisTtlSecs) -}}
{{- end -}}
{{/* L2 — Postgres */}}
{{- $l2 := dict "type" "pg" "url" (include "super-cache-ci.postgresUrl" .) "max_conns" (int $s.postgresMaxConns) -}}
{{/* L3 — object tier (s3) or local sentinel when disabled */}}
{{- $l3kind := (($s.l3).kind | default "disabled") -}}
{{- $l3 := dict -}}
{{- if eq $l3kind "s3" -}}
{{- $l3 = dict "type" "s3" "bucket" $s.l3.s3.bucket "region" $s.l3.s3.region -}}
{{- if and (hasKey $s.l3.s3 "endpoint") (ne (toString $s.l3.s3.endpoint) "") -}}
{{- $_ := set $l3 "endpoint" $s.l3.s3.endpoint -}}
{{- end -}}
{{- else -}}
{{/* No object tier: the L3 slot is a local sentinel so a triple-tier miss
     terminates deterministically at re-derivation rather than a network fetch. */}}
{{- $l3 = dict "type" "local" "path" "/var/cache/sui/l3" -}}
{{- end -}}
{{- $tiered := dict "type" "tiered" "l1" $l1 "l2" $l2 "l3" $l3 "write_policy" ($s.writePolicy | default "write-through") -}}
{{- $tiered | toJson -}}
{{- end -}}
