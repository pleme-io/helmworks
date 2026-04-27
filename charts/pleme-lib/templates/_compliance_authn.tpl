{{/*
pleme-lib: compliance — authentication primitives

Foundation primitive: every chart that exposes an external Service or
that participates in service-to-service auth composes against these.

Maps to NIST 800-53 controls:
  IA-2     — Identification and Authentication of Organizational Users:
             OIDC SSO required at moderate+ for human-facing UIs
  IA-2(1)  — Multi-Factor Authentication: enforced upstream by the OIDC
             provider (Authentik in pleme-io)
  IA-3     — Device Identification and Authentication: mTLS between
             services (Istio PeerAuthentication=STRICT)
  IA-5     — Authenticator Management: short-lived projected SA tokens
             with explicit audience
  SC-8     — Transmission Confidentiality: TLS / mTLS
  SC-13    — Cryptographic Protection: TLS 1.2+ at moderate, 1.3 at high
  AC-17    — Remote Access: external Ingress must auth-gate

Three shapes:
  authn.oidc      — Authentik forward-auth annotations for an Ingress
  authn.istio.mtls — PeerAuthentication=STRICT for service-to-service
  authn.token     — projected SA token with audience for downstream auth
*/}}

{{/*
Authentik forward-auth annotations for an nginx-ingress Ingress.

Required fields under .Values.compliance.authn.oidc:
  provider     — "authentik" (only supported today)
  outpostHost  — Authentik embedded outpost service hostname
                 (default: "authentik.identity.svc.cluster.local")
  outpostPort  — Authentik embedded outpost port (default: 9000)
  group        — required Authentik group for access (optional)

Returns annotation keys/values to merge into Ingress metadata.annotations.
*/}}
{{- define "pleme-lib.compliance.authn.oidcAnnotations" -}}
{{- $oidc := ((.Values.compliance).authn).oidc | default dict -}}
{{- if $oidc.provider }}
{{- $host := $oidc.outpostHost | default "authentik.identity.svc.cluster.local" -}}
{{- $port := $oidc.outpostPort | default 9000 -}}
nginx.ingress.kubernetes.io/auth-url: "http://{{ $host }}:{{ $port }}/outpost.goauthentik.io/auth/nginx"
nginx.ingress.kubernetes.io/auth-signin: "https://$host/outpost.goauthentik.io/start?rd=$escaped_request_uri"
nginx.ingress.kubernetes.io/auth-response-headers: "Set-Cookie,X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid"
nginx.ingress.kubernetes.io/auth-snippet: |
  proxy_set_header X-Forwarded-Host $http_host;
{{- if $oidc.group }}
nginx.ingress.kubernetes.io/auth-snippet-extra: |
  proxy_set_header X-authentik-required-group {{ $oidc.group | quote }};
{{- end }}
{{- end }}
{{- end }}

{{/*
Istio PeerAuthentication: STRICT mTLS for the workload's pods.

At fedramp-high, mTLS is mandatory for service-to-service traffic.
Emitted when .Values.compliance.authn.istio.mtls.required = true OR
when baseline >= fedramp-high.
*/}}
{{- define "pleme-lib.compliance.authn.peerAuthentication" -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $istio := ((.Values.compliance).authn).istio | default dict -}}
{{- $mtls := $istio.mtls | default dict -}}
{{- $required := false -}}
{{- if eq $atLeastHigh "true" }}{{ $required = true }}{{ end -}}
{{- if eq (toString $mtls.required) "true" }}{{ $required = true }}{{ end -}}
{{- if eq (toString $mtls.required) "false" }}{{ $required = false }}{{ end -}}
{{- if $required }}
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: {{ include "pleme-lib.fullname" . }}-mtls-strict
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  mtls:
    mode: {{ $mtls.mode | default "STRICT" }}
{{- end }}
{{- end }}

{{/*
Projected ServiceAccount token volume with explicit audience.

Returns a `volumes:` entry to merge into the pod spec. Used by workloads
that need to present an SA token to a downstream service (e.g. Zot, the
internal auth gateway). The audience is required so that the token
cannot be replayed against unrelated services.

Required fields under .Values.compliance.authn.token:
  audience — the audience the token is bound to (e.g. "zot.cluster.local")
  expirationSeconds — TTL (default: 3600 = 1h)
  path — mount path for the token file (default: /var/run/secrets/<audience>)
*/}}
{{- define "pleme-lib.compliance.authn.tokenVolume" -}}
{{- $tok := ((.Values.compliance).authn).token | default dict -}}
{{- if $tok.audience }}
- name: token-{{ $tok.audience | replace "." "-" | replace "/" "-" | trunc 60 | trimSuffix "-" }}
  projected:
    sources:
      - serviceAccountToken:
          audience: {{ $tok.audience | quote }}
          expirationSeconds: {{ $tok.expirationSeconds | default 3600 }}
          path: token
{{- end }}
{{- end }}

{{/*
Validate.

At fedramp-moderate+:
  - If ingress.enabled = true AND compliance.authn.oidc not configured,
    fail. External Ingress must have authn.

At fedramp-high:
  - Token TTL must be ≤ 3600s (1h)
*/}}
{{- define "pleme-lib.compliance.authn.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $authn := (.Values.compliance).authn | default dict -}}
{{- if eq $atLeastMod "true" -}}
  {{- $ing := .Values.ingress | default dict -}}
  {{- if eq (toString $ing.enabled) "true" -}}
    {{- $oidc := $authn.oidc | default dict -}}
    {{- $allow := $authn.allowList | default dict -}}
    {{- if and (not $oidc.provider) (not $allow.unauthenticatedIngress) -}}
      {{- fail (printf "compliance: baseline=%s requires compliance.authn.oidc.provider when ingress.enabled=true (IA-2, AC-17); set compliance.authn.allowList.unauthenticatedIngress=true to opt out (e.g. for public marketing pages)" $b) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if eq $atLeastHigh "true" -}}
  {{- $tok := $authn.token | default dict -}}
  {{- if $tok.audience -}}
    {{- $ttl := $tok.expirationSeconds | default 3600 | int -}}
    {{- if gt $ttl 3600 -}}
      {{- fail (printf "compliance: baseline=fedramp-high requires SA token TTL <= 3600s (IA-5); got %d" $ttl) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
