{{/*
pleme-lib.dataLifecycleBundle — the data-plane analog of observabilityBundle.

ONE typed border (`.Values.dataLifecycle`) synthesizes the whole durable-data
lifecycle of a service by delegating to the existing pleme-lib primitives:

  - migration → `pleme-lib.shinkaDatabaseMigration` (the shinka DatabaseMigration
    CR + the migrate→wait→serve gate; the migrators[] sqlx→seaorm cutover).
  - breathe   → `pleme-lib.breatheBand` (the data-tier carving band — a
    StorageBand on the DB's PVC, or a MemoryBand on the DB Cluster).
  - secret    → `pleme-lib.externalSecret` (the DB-credentials ExternalSecret,
    cofre/ESO-materialized — zero-plaintext per the cofre discipline).

Each leg is independently gated and OFF by default, so a service that needs only
a subset (M0 in-memory: none; M1: migration; M2: + breathe + secret) declares
exactly what it uses. Same synthesize-the-WHAT-from-typed-values /
delegate-HOW-to-the-primitive / orthogonal-toggles shape as observabilityBundle.

Usage — the consuming chart's templates/data-lifecycle.yaml is one line:
  {{- include "pleme-lib.dataLifecycleBundle" . }}

values.yaml:
  dataLifecycle:
    migration:                 # → shinkaMigration value path
      enabled: true
      database: { cnpgClusterRef: { name: pangea-database, database: catch } }
      migrators: [ ... ]
    breathe:                   # → breathe value path (data-tier band)
      enabled: true
      dimension: storage
      targetRef: { name: pangea-database }
    secret:                    # → externalSecret value path
      secrets:
        db-credentials: { ... }
*/}}
{{- define "pleme-lib.dataLifecycleBundle" -}}
{{- $dl := .Values.dataLifecycle | default dict -}}
{{- $migration := $dl.migration | default dict -}}
{{- $breathe := $dl.breathe | default dict -}}
{{- $secret := $dl.secret | default dict -}}
{{/* augmented Values so each delegated primitive finds its own value path */}}
{{- $V := deepCopy .Values -}}
{{- $_ := set $V "shinkaMigration" $migration -}}
{{- $_ := set $V "breathe" $breathe -}}
{{- $_ := set $V "externalSecret" $secret -}}
{{- $ctx := dict "Values" $V "Chart" .Chart "Release" .Release "Template" .Template "Capabilities" .Capabilities "Files" .Files -}}
{{- if $migration.enabled }}
---
{{ include "pleme-lib.shinkaDatabaseMigration" $ctx -}}
{{- end }}
{{- if $breathe.enabled }}
---
{{ include "pleme-lib.breatheBand" $ctx -}}
{{- end }}
{{- if $secret.secrets }}
---
{{ include "pleme-lib.externalSecret" $ctx -}}
{{- end }}
{{- end -}}
