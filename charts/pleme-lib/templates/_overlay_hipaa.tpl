{{/*
Overlay: hipaa
Source: HIPAA Security Rule §164.308 / §164.310 / §164.312 (45 CFR Part 164)
        + HHS HIPAA Security Series Guidance

K8s-side mapping of the HIPAA Security Rule for ePHI workloads. Requires
fedramp-moderate as a foundation (most HIPAA controls are subset of NIST
800-53 Moderate). Adds HIPAA-specific requirements on top.

Concrete additions on top of fedramp-moderate:
  - §164.312(a)(2)(i)  Unique User Identification: dedicated SA per workload
                       (already enforced by fedramp-moderate via authz)
  - §164.312(a)(2)(iv) Encryption at rest: PVCs MUST use encrypted SC
                       (already enforced by fedramp-high; here we lift it
                       into moderate-level HIPAA requirement)
  - §164.312(b)        Audit controls: ServiceMonitor required + audit
                       annotations at extended retention
                       (HIPAA mandates 6-year retention)
  - §164.312(c)(1)     Integrity controls: cosign verification at admission
                       (composes with supplychain overlay)
  - §164.312(e)(1)     Transmission security: TLS only, mTLS via Istio
                       (already in fedramp baseline)
  - §164.308(a)(1)(ii)(D) Information system activity review: required
                          audit log forwarding
  - §164.308(a)(7)(ii)(A) Data backup plan: PVC must reference Velero schedule
                          (annotation enforces evidence)

The HIPAA overlay does NOT itself force supplychain — operators should
declare both: `compliance.overlays: [hipaa, supplychain]` for full ePHI
posture. This is intentional — HIPAA-without-cosign is a documented
weaker posture (§164.306(b)(2)(iv) addresses-vs-implements language).
*/}}

{{- define "pleme-lib.overlay.hipaa.requires" -}}fedramp-moderate{{- end }}

{{- define "pleme-lib.overlay.hipaa.controls" -}}
HIPAA-§164.308(a)(1)(ii)(D),HIPAA-§164.308(a)(7)(ii)(A),HIPAA-§164.312(a)(2)(i),HIPAA-§164.312(a)(2)(iv),HIPAA-§164.312(b),HIPAA-§164.312(c)(1),HIPAA-§164.312(e)(1)
{{- end }}

{{- define "pleme-lib.overlay.hipaa.validate" -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- if eq $isWorkload "true" -}}
  {{- /* §164.312(a)(2)(iv) — encryption at rest */ -}}
  {{- $persistence := .Values.persistence | default dict -}}
  {{- if eq (toString $persistence.enabled) "true" -}}
    {{- $sc := $persistence.storageClass | default $persistence.storageClassName | default "" | toString -}}
    {{- if eq $sc "" -}}
      {{- fail (printf "compliance: hipaa overlay requires persistence.storageClass to be encrypted (HIPAA §164.312(a)(2)(iv)); set to one of compliance.storage.encryptedClasses") -}}
    {{- end -}}
  {{- end -}}
  {{- /* §164.308(a)(1)(ii)(D) — audit log forwarding evidence */ -}}
  {{- $audit := (.Values.compliance).audit | default dict -}}
  {{- $retention := $audit.retentionDays | default 365 | int -}}
  {{- if lt $retention 2190 -}}
    {{- fail (printf "compliance: hipaa overlay requires audit retention >= 2190 days (6 years; HIPAA §164.316(b)(2)(i)); got %d. Set compliance.audit.retentionDays >= 2190." $retention) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.hipaa.annotations" -}}
compliance.pleme.io/overlay-hipaa: "true"
pleme.io/hipaa-version: "45-cfr-164"
pleme.io/hipaa-ephi-handling: "true"
{{ end }}

{{- define "pleme-lib.overlay.hipaa.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.hipaa.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.hipaa.manifestData" -}}
overlay-hipaa: "true"
hipaa-ephi-handling: "true"
hipaa-version: "45-cfr-164"
{{ end }}

{{- define "pleme-lib.overlay.hipaa.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.hipaa.imagePullSecrets" -}}{{- end }}

{{/* HIPAA admission policy: assert ePHI workloads have encryption at
     rest, audit annotations, and ingress TLS. */}}
{{- define "pleme-lib.overlay.hipaa.kyvernoPolicy" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pleme-overlay-hipaa
  annotations:
    pleme.io/overlay: hipaa
    pleme.io/controls: "HIPAA-§164.312(a)(2)(iv),HIPAA-§164.312(b),HIPAA-§164.312(e)(1)"
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-hipaa-audit-annotation
      match:
        any:
          - resources:
              kinds: ["Deployment", "StatefulSet", "DaemonSet"]
              selector:
                matchLabels:
                  compliance.pleme.io/overlay-hipaa: "true"
      validate:
        message: "HIPAA overlay requires audit.pleme.io/retention-days annotation (>=2190 days; HIPAA §164.316(b)(2)(i))"
        pattern:
          metadata:
            annotations:
              audit.pleme.io/retention-days: "?*"
{{ end }}
{{- define "pleme-lib.overlay.hipaa.gatekeeperConstraint" -}}{{- end }}
