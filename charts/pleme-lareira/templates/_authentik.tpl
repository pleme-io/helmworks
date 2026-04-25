{{/*
pleme-lareira.authentik.annotations — nginx-ingress forward-auth wiring.

When .Values.authentik.enabled is true, emit the nginx auth-url and
auth-signin annotations that proxy unauthenticated requests through the
Authentik embedded outpost. Designed to be merged into an Ingress's
annotations block by `pleme-lareira.ingress`.

The outpost URL defaults to the in-cluster Service produced by the
official authentik Helm chart (auth.example.com → embedded outpost). If
the consumer overrides authentik.authRequestUrl / authentik.authSigninUrl
explicitly, those win; otherwise we derive sensible defaults from
authentik.outpostUrl.

Reference (nginx forward-auth flow):
  https://goauthentik.io/docs/providers/proxy/server_nginx/#nginx-ingress
*/}}

{{- define "pleme-lareira.authentik.annotations" -}}
{{- if .Values.authentik.enabled }}
{{- $outpost := .Values.authentik.outpostUrl }}
{{- $authRequest := .Values.authentik.authRequestUrl | default (printf "%s/outpost.goauthentik.io/auth/nginx" $outpost) }}
{{- $authSignin := .Values.authentik.authSigninUrl | default (printf "%s/outpost.goauthentik.io/start?rd=$escaped_request_uri" $outpost) }}
nginx.ingress.kubernetes.io/auth-url: {{ $authRequest | quote }}
nginx.ingress.kubernetes.io/auth-signin: {{ $authSignin | quote }}
nginx.ingress.kubernetes.io/auth-response-headers: "Set-Cookie,X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid"
nginx.ingress.kubernetes.io/auth-snippet: |
  proxy_set_header X-Forwarded-Host $http_host;
{{- end }}
{{- end -}}
