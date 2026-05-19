{{/*
pleme-lib: networkpolicy named templates

Provides deny-all base + selective allow rules.
Follows the pattern from k8s repo governance network policies.
*/}}

{{/*
Default deny-all NetworkPolicy.

When `.Values.compliance.baseline` is at moderate+, NetworkPolicy is rendered
unconditionally (the deny-all + allow-dns + allow-tls-egress trio comes from
_compliance_network.tpl, plus any consumer-provided additionalIngress / Egress
rules below).
*/}}
{{- define "pleme-lib.networkpolicy" -}}
{{- $complianceRequired := include "pleme-lib.compliance.network.required" . -}}
{{- if eq $complianceRequired "true" -}}
{{ include "pleme-lib.compliance.network.policies" . }}
{{- /* Layer 1: generic egress shapes (toService / toUpstream) */ -}}
{{ include "pleme-lib.compliance.egress.policies" . }}
{{- /* Layer 2: air-gap shapes (consumer / registry-mirror) */ -}}
{{ include "pleme-lib.compliance.airgap.policies" . }}
{{- range (.Values.networkPolicy).additionalIngress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" $ | nindent 6 }}
  policyTypes:
    - Ingress
  ingress:
    {{- toYaml .rules | nindent 4 }}
{{- end }}
{{- range (.Values.networkPolicy).additionalEgress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" $ | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    {{- toYaml .rules | nindent 4 }}
{{- end }}
{{- else if (.Values.networkPolicy).enabled }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-deny-all
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
{{- if (.Values.networkPolicy).allowDns }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-dns
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
{{- end }}
{{- if (.Values.networkPolicy).allowPrometheus }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-prometheus
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: prometheus-operator
        {{- range (.Values.networkPolicy).prometheusNamespaces }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ . }}
        {{- end }}
      ports:
        - port: {{ (.Values.monitoring).port | default "http" }}
          protocol: TCP
{{- end }}
{{- /*
  allowEgressHttps — "talks to public API" shape that doesn't fit
  compliance.egress.toUpstream's allowlist model. Emits one
  NetworkPolicy allowing TCP 443 egress to 0.0.0.0/0 except RFC1918 +
  link-local ranges. Use for charts that egress to public-internet
  APIs (Hashnode, GitHub, third-party SaaS) without enumerating the
  upstream CIDRs.

  At fedramp-moderate+ baseline, prefer compliance.egress.toUpstream
  with a curated allowedCidrs list (auditable, principle-of-least-
  privilege). This helper is the not-yet-curated path.
*/}}
{{- if (.Values.networkPolicy).allowEgressHttps }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-egress-https
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
              - 169.254.0.0/16
      ports:
        - protocol: TCP
          port: 443
{{- end }}
{{- range (.Values.networkPolicy).additionalIngress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" $ | nindent 6 }}
  policyTypes:
    - Ingress
  ingress:
    {{- toYaml .rules | nindent 4 }}
{{- end }}
{{- range (.Values.networkPolicy).additionalEgress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" $ | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    {{- toYaml .rules | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}
