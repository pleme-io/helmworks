{{/*
lareira-mesh-spec — helpers for the per-mesh declaration.
*/}}

{{/*
Aggregate the full peer+upstream allowlist:
   trust-domain → mesh.namespace × all servicos[].sa
                 + each participant.namespace × participant.sa
*/}}
{{- define "lareira-mesh-spec.allSpiffeIds" -}}
{{- $td := .Values.mesh.trustDomain -}}
{{- $homeNs := .Values.mesh.namespace -}}
{{- $ids := list -}}
{{- range .Values.servicos -}}
{{- $ids = append $ids (printf "spiffe://%s/ns/%s/sa/%s" $td $homeNs .serviceAccount) -}}
{{- end -}}
{{- range .Values.participants -}}
{{- $ids = append $ids (printf "spiffe://%s/ns/%s/sa/%s" $td .namespace .serviceAccount) -}}
{{- end -}}
{{- $ids | uniq | toJson -}}
{{- end }}

{{/*
Render the ConfigMap data for the aresta config — used by both the
home-ns CM and each participant's CM.
*/}}
{{- define "lareira-mesh-spec.arestaConfigYaml" -}}
{{- $idsJson := include "lareira-mesh-spec.allSpiffeIds" . -}}
{{- $ids := fromJsonArray $idsJson -}}
identity:
  peer_allowlist:
    {{- range $ids }}
    - {{ . | quote }}
    {{- end }}
  upstream_allowlist:
    {{- range $ids }}
    - {{ . | quote }}
    {{- end }}
  workload_api_socket: null
inbound_addr: {{ .Values.arestaConfig.inboundAddr | quote }}
outbound_addr: {{ .Values.arestaConfig.outboundAddr | quote }}
probe_addr: {{ .Values.arestaConfig.probeAddr | quote }}
observability:
  log_format: {{ .Values.arestaConfig.observability.logFormat | quote }}
  metrics_addr: {{ .Values.arestaConfig.observability.metricsAddr | quote }}
policy:
  circuit_breaker_max_failures: {{ .Values.arestaConfig.policy.circuitBreakerMaxFailures }}
  max_retries: {{ .Values.arestaConfig.policy.maxRetries }}
  request_timeout: {{ .Values.arestaConfig.policy.requestTimeout | quote }}
upstream_addr: {{ .Values.arestaConfig.fallbackUpstreamAddr | quote }}
{{- end }}

{{/*
SPIFFE-ID template handed to spire-controller-manager. The
`{{ .TrustDomain }}`, `{{ .PodMeta.Namespace }}`, and
`{{ .PodSpec.ServiceAccountName }}` substitutions are evaluated by
the controller, NOT Helm. Escape with backticks so Helm doesn't try
to render them.
*/}}
{{- define "lareira-mesh-spec.spiffeIdTemplate" -}}
{{- printf "%s" "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}" -}}
{{- end }}

{{/*
Deduplicated list of every namespace participating in the mesh:
the home namespace plus every cross-namespace participant. Used to
fan out per-namespace ClusterRoleBindings + NetworkPolicies.

Returns a JSON array (toJson + fromJsonArray round-trip) so callers
can `range` over it without re-computing.
*/}}
{{- define "lareira-mesh-spec.allNamespaces" -}}
{{- $ns := list .Values.mesh.namespace -}}
{{- range .Values.participants -}}
{{- $ns = append $ns .namespace -}}
{{- end -}}
{{- $ns | uniq | toJson -}}
{{- end }}
