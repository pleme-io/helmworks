{{/*
pleme-lib: istio named templates

PeerAuthentication and DestinationRule for Istio service mesh.
*/}}

{{/*
PeerAuthentication — mTLS mode with optional per-port overrides
*/}}
{{- define "pleme-lib.peerAuthentication" -}}
{{- if (.Values.istio).enabled }}
{{- $fullname := include "pleme-lib.fullname" . -}}
{{- range (.Values.istio).peerAuthentication | default (list (dict "name" $fullname "mtls" "STRICT")) }}
---
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: {{ .name | default $fullname }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" $ | nindent 6 }}
  mtls:
    mode: {{ .mtls | default "STRICT" }}
  {{- with .portLevelMtls }}
  portLevelMtls:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
DestinationRule — circuit breaking, connection pooling, outlier detection, TLS mode
*/}}
{{- define "pleme-lib.destinationRule" -}}
{{- if (.Values.istio).enabled }}
{{- $fullname := include "pleme-lib.fullname" . -}}
{{- range (.Values.istio).destinationRules | default list }}
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: {{ .name | default $fullname }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  host: {{ .host | default (printf "%s.%s.svc.cluster.local" $fullname (include "pleme-lib.namespace" $)) }}
  {{- with .trafficPolicy }}
  trafficPolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
