{{- /*
pleme-lareira.allResources

Renders the standard set of K8s resources for a home-services workload by
delegating to pleme-lib (deployment, service, networkpolicy, etc.) and
pleme-lareira (ingress, pvc, restic-cronjob, alerts, breathability-cron).

Service charts that use this helper need only ONE template file:

    templates/all.yaml:
      {{ include "pleme-lareira.enabled" . | required-style guard }}
      {{ include "pleme-lareira.allResources" . }}

Every contained resource is itself gated on the relevant
.Values.<feature>.enabled flag, so a chart with everything off renders
empty. The outer master toggle is .Values.enabled.

Resources rendered (each conditional):
  - pleme-lib.deployment        (always when master enabled=true)
  - pleme-lib.service           (always)
  - pleme-lib.serviceaccount    (always; pleme-lib internal toggle)
  - pleme-lib.networkpolicy     (when networkPolicy.enabled)
  - pleme-lib.servicemonitor    (when monitoring.enabled)
  - pleme-lib.pdb               (when pdb.enabled)
  - pleme-lib.breathability     (when breathability.enabled, NATS trigger)
  - pleme-lareira.breathability.cron  (when breathability.cron.enabled)
  - pleme-lareira.ingress       (when ingress.enabled)
  - pleme-lareira.pvc           (when persistence.enabled)
  - pleme-lareira.restic.cronjob (when backup.enabled)
  - pleme-lareira.alerts.common (when alerts.common.enabled AND prometheusRules.enabled)

Service-chart-specific resources (Secrets pre-rendered by SOPS, custom
ConfigMaps, sidecar Deployments, etc.) should live in additional
templates/*.yaml files alongside templates/all.yaml — this helper is the
common-case shortcut, not a one-size-fits-all.
*/ -}}

{{- define "pleme-lareira.allResources" -}}
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lib.deployment" . }}
---
{{- include "pleme-lib.service" . }}
---
{{- include "pleme-lib.serviceaccount" . }}
{{- if .Values.networkPolicy.enabled }}
---
{{- include "pleme-lib.networkpolicy" . }}
{{- end }}
{{- if .Values.monitoring.enabled }}
---
{{- include "pleme-lib.servicemonitor" . }}
{{- end }}
{{- if .Values.pdb.enabled }}
---
{{- include "pleme-lib.pdb" . }}
{{- end }}
{{- if .Values.breathability.enabled }}
{{- include "pleme-lib.breathability" . }}
{{- end }}
{{- include "pleme-lareira.breathability.cron" . }}
{{- include "pleme-lareira.ingress" . }}
{{- include "pleme-lareira.pvc" . }}
{{- include "pleme-lareira.restic.cronjob" . }}
{{- include "pleme-lareira.alerts.common" . }}
{{- end }}
{{- end -}}
