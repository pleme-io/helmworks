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

{{/*
lareira-clickhouse.securityContext — render a container securityContext, or FAIL.

WHY THIS EXISTS. Every call site previously spelled this as

    {{- with $ch.securityContext }}
    securityContext:
      {{- toYaml . | nindent 12 }}
    {{- end }}

and a `with` block renders NOTHING when its subject is empty. Measured
2026-08-02 on this chart: `--set clickhouse.securityContext=null` drops the
rendered container hardening from 4 lines to 1 -- readOnlyRootFilesystem,
capabilities.drop [ALL] and allowPrivilegeEscalation false all disappear --
while `helm template` exits 0 with ZERO bytes of stderr. The manifest stays
valid, the pod starts, and `kubectl get statefulset` shows it healthy. A
single values override silently un-hardens the workload and nothing anywhere
says so.

That is the same failure shape this program keeps finding: the absence of a
control is indistinguishable from its presence at every layer that looks.

So absence is now a RENDER-TIME FAILURE, and the required keys are named
individually rather than checked as a lump -- a securityContext that exists
but has lost `capabilities` is exactly as unhardened as one that is missing,
and would otherwise pass a non-empty check.

Not claimed: that this validates the VALUES (runAsUser: 0 would still
render). It closes absence, not misconfiguration.
*/}}
{{- define "lareira-clickhouse.securityContext" -}}
{{- $sc := . -}}
{{- if not $sc -}}
{{- fail "lareira-clickhouse: securityContext is empty or absent. A `with` block would render nothing here and the container would run UNHARDENED with a valid manifest and a green pod. Set it explicitly; see values.yaml." -}}
{{- end -}}
{{- range $k := list "readOnlyRootFilesystem" "allowPrivilegeEscalation" "capabilities" -}}
{{- if not (hasKey $sc $k) -}}
{{- fail (printf "lareira-clickhouse: securityContext is missing required key %q. Present-but-incomplete is as unhardened as absent, and a non-empty check would not catch it." $k) -}}
{{- end -}}
{{- end -}}
{{- toYaml $sc -}}
{{- end -}}
