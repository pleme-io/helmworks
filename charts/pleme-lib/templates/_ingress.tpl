{{/*
pleme-lib: ingress named template

Renders a v1 Ingress for services that face the cluster edge. Disabled
by default; enable via `.Values.ingress.enabled = true` and declare
hosts.

Per-path service port resolution (innermost first):
  1. `.servicePortName` — explicit named port from `.Values.service.ports[*].name`
  2. `.servicePort`     — explicit numeric port
  3. fallback           — first entry in `.Values.service.ports[]` —
                          use its name when targetPort is set, otherwise
                          the port number

This means a chart that declares one named http port in `.service.ports`
gets a working Ingress with zero per-path port plumbing — set `enabled`
and `hosts`, done.

Values schema:

  ingress:
    enabled: false
    className: nginx              # optional
    annotations: {}               # merged with pleme-lib.resourceAnnotations
    tls: []                       # standard Ingress tls block (list)
    hosts:                        # list
      - host: example.com
        paths:
          - path: /
            pathType: Prefix
            # servicePortName: http   # OR
            # servicePort: 8080

Compliance integration:
  - `compliance.ingress.tls.required = true` enforces non-empty `tls`
    at fedramp-moderate+ via `pleme-lib.compliance.ingress.validate`
    (see _compliance_ingress.tpl). This template does not duplicate
    that validation; the consumer chart imports the validator from
    `pleme-lib.compliance.validate` at compliance baseline ≥ moderate.
*/}}

{{- define "pleme-lib.ingress" -}}
{{- if (.Values.ingress).enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- $resAnnotations := include "pleme-lib.resourceAnnotations" . | trim }}
  {{- $userAnnotations := (.Values.ingress).annotations }}
  {{- if or $resAnnotations $userAnnotations }}
  annotations:
    {{- if $resAnnotations }}
    {{- $resAnnotations | nindent 4 }}
    {{- end }}
    {{- with $userAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
spec:
  {{- with (.Values.ingress).className }}
  ingressClassName: {{ . }}
  {{- end }}
  {{- with (.Values.ingress).tls }}
  tls:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  rules:
    {{- range (.Values.ingress).hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ include "pleme-lib.fullname" $ }}
                port:
                  {{- if .servicePortName }}
                  name: {{ .servicePortName }}
                  {{- else if .servicePort }}
                  number: {{ .servicePort }}
                  {{- else }}
                  {{- $firstPort := (index ($.Values.service.ports | default list) 0) | default dict }}
                  {{- if $firstPort.name }}
                  name: {{ $firstPort.name }}
                  {{- else if $firstPort.port }}
                  number: {{ $firstPort.port }}
                  {{- else }}
                  number: 80
                  {{- end }}
                  {{- end }}
          {{- end }}
    {{- end }}
{{- end }}
{{- end }}
