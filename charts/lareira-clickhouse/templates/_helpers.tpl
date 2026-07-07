{{/*
_helpers.tpl — lareira-clickhouse local names on top of the pleme-lib base.

Lake mode ("keeper.enabled") introduces a second StatefulSet (Keeper) and needs
stable per-pod DNS for both tiers, so the chart names the data + Keeper services
+ StatefulSets here rather than inline in every template.
*/}}

{{/* The data StatefulSet name (== the base fullname; the tap store's identity). */}}
{{- define "lareira-clickhouse.data.fullname" -}}
{{- include "pleme-lib.fullname" . -}}
{{- end -}}

{{/* The headless service giving each data replica stable pod DNS
     (data-<n>.<data.headless>). Required for remote_servers + ReplicatedMergeTree. */}}
{{- define "lareira-clickhouse.data.headless" -}}
{{- printf "%s-headless" (include "pleme-lib.fullname" .) -}}
{{- end -}}

{{/* The Keeper StatefulSet name. */}}
{{- define "lareira-clickhouse.keeper.fullname" -}}
{{- printf "%s-keeper" (include "pleme-lib.fullname" .) -}}
{{- end -}}

{{/* The Keeper headless service (keeper-<n>.<keeper.headless> pod DNS). */}}
{{- define "lareira-clickhouse.keeper.headless" -}}
{{- printf "%s-keeper" (include "pleme-lib.fullname" .) -}}
{{- end -}}

{{/*
The data StatefulSet replica count.
  • tap  (keeper disabled): 0 — KEDA owns the replica count (zero-scale).
  • lake (keeper enabled):  clickhouse.topology.replicasPerShard — a fixed HA
    floor (a sleeping replica cannot hold a Keeper-coordinated seat), KEDA off.
The interim realizes ONE logical shard; multi-shard is the D1 operator target.
*/}}
{{- define "lareira-clickhouse.data.replicas" -}}
{{- if .Values.clickhouse.keeper.enabled -}}
{{- .Values.clickhouse.topology.replicasPerShard | default 1 -}}
{{- else -}}
0
{{- end -}}
{{- end -}}

{{/* True when the store runs the lake posture (Keeper-coordinated ReplicatedMergeTree). */}}
{{- define "lareira-clickhouse.lake" -}}
{{- and .Values.clickhouse.keeper.enabled .Values.clickhouse.replication.enabled -}}
{{- end -}}
