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
