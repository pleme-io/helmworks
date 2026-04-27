{{/*
pleme-lib: compliance — audit primitives

Maps to NIST 800-53 controls:
  AU-2  — Audit Events: workload metrics endpoint scraped + structured logs
  AU-3  — Content of Audit Records: required pod labels (app, version, env)
  AU-11 — Audit Record Retention: retention enforced cluster-side, but the
          workload must emit the records — that's what ServiceMonitor does.
  AU-12 — Audit Record Generation: every workload emits audit-suitable logs
  SI-4  — System Monitoring: Prometheus scrape + alert routing

At moderate+, ServiceMonitor / PodMonitor is mandatory. Without monitoring
we cannot prove SI-4, AU-2, AU-12 — the workload would be a blind spot.
*/}}

{{/*
Whether monitoring is mandatory at the current baseline.
*/}}
{{- define "pleme-lib.compliance.audit.required" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- if eq $atLeastMod "true" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Audit-related annotations. Surface log-pipeline metadata that Vector / Splunk /
Datadog readers consume.
*/}}
{{- define "pleme-lib.compliance.audit.annotations" -}}
{{- $required := include "pleme-lib.compliance.audit.required" . -}}
{{- if eq $required "true" }}
audit.pleme.io/log-format: "json"
audit.pleme.io/log-level: {{ ((.Values.compliance).audit).logLevel | default "info" | quote }}
audit.pleme.io/retention-days: {{ ((.Values.compliance).audit).retentionDays | default 365 | quote }}
{{- end }}
{{- end }}

{{/*
Validate.
*/}}
{{- define "pleme-lib.compliance.audit.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $required := include "pleme-lib.compliance.audit.required" . -}}
{{- if eq $required "true" -}}
  {{- $mon := .Values.monitoring | default dict -}}
  {{- $pm := .Values.podMonitor | default dict -}}
  {{- $audit := (.Values.compliance).audit | default dict -}}
  {{/* Acceptable audit signals (any one suffices):
         1. monitoring.enabled=true               (ServiceMonitor)
         2. podMonitor.enabled=true               (PodMonitor — for pods without a Service)
         3. compliance.audit.viaJobEvents=true    (CronJob/Job — audited via kube-state-metrics + structured logs)
       The validator fails only if NONE of these is satisfied. */}}
  {{- $hasMonitoring := and (hasKey $mon "enabled") (eq (toString $mon.enabled) "true") -}}
  {{- $hasPodMonitor := and (hasKey $pm "enabled") (eq (toString $pm.enabled) "true") -}}
  {{- $viaJob := eq (toString $audit.viaJobEvents) "true" -}}
  {{- if not (or (or $hasMonitoring $hasPodMonitor) $viaJob) -}}
    {{- fail (printf "compliance: baseline=%s requires an audit signal: monitoring.enabled=true OR podMonitor.enabled=true OR compliance.audit.viaJobEvents=true (AU-2, AU-12, SI-4)" $b) -}}
  {{- end -}}
{{- end -}}
{{- end }}
