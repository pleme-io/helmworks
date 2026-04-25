{{/*
pleme-lareira.cloudflared.serviceAnnotations — mark a Service for tunnel exposure.

The cloudflared daemon runs on the HOST (NixOS module on rio), not as a
Pod — that's an intentional pleme-io decision because the tunnel binds
privileged ports and owns the ISP link, and putting it in a Pod fights
the tunnel ownership model.

This helper emits annotations on the Service that the host-side
cloudflared config-reconciler (`seibi cloudflared-reconcile` or similar)
reads to populate the tunnel's `config.yml` ingress list. Each annotated
Service contributes one ingress rule:

  hostname: <pleme.cloudflared/hostname>
  service:  http://<service-fqdn>:<port>

Use in consumer chart templates/service.yaml:

  apiVersion: v1
  kind: Service
  metadata:
    annotations:
      {{- include "pleme-lareira.cloudflared.serviceAnnotations" . | nindent 4 }}

When .Values.cloudflared.expose is false, this helper renders nothing.

Cloudflare Access (zero-trust SSO without running Authentik) is opt-in
via .Values.cloudflared.accessApp — if set, the reconciler is expected
to gate the tunnel ingress behind a CF Access policy app of that name.
*/}}

{{- define "pleme-lareira.cloudflared.serviceAnnotations" -}}
{{- if .Values.cloudflared.expose }}
{{- $hostname := required "cloudflared.expose=true requires cloudflared.hostname" .Values.cloudflared.hostname }}
pleme.cloudflared/expose: "true"
pleme.cloudflared/hostname: {{ $hostname | quote }}
{{- with .Values.cloudflared.port }}
pleme.cloudflared/port: {{ . | quote }}
{{- end }}
{{- with .Values.cloudflared.accessApp }}
pleme.cloudflared/access-app: {{ . | quote }}
{{- end }}
{{- end }}
{{- end -}}
