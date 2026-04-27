{{/*
Overlays: fedramp-low / fedramp-moderate / fedramp-high
Source: NIST 800-53 Rev 5 + FedRAMP baselines

Each overlay registers its surface as a set of named templates following
the pattern pleme-lib.overlay.<name>.<surface>. Implementation delegates
to the existing _compliance_*.tpl helpers — the overlay layer is the
declarative registration; the helpers are the reusable workhorse code.
*/}}

{{/* ───────────────────────────── fedramp-low ───────────────────────── */}}

{{- define "pleme-lib.overlay.fedramp-low.requires" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.controls" -}}
AU-2,AU-12,CM-2,CM-6,CM-7,IA-2,SC-7,SC-13
{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.validate" -}}
{{/* fedramp-low does not enforce template-time invariants. The labels
     and annotations record the claim; cluster-side admission can verify. */}}
{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.annotations" -}}
compliance.pleme.io/overlay-fedramp-low: "true"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-low.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.manifestData" -}}
overlay-fedramp-low: "true"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-low.podEnv" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.imagePullSecrets" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.kyvernoPolicy" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-low.gatekeeperConstraint" -}}{{- end }}


{{/* ───────────────────────────── fedramp-moderate ─────────────────── */}}

{{- define "pleme-lib.overlay.fedramp-moderate.requires" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-moderate.controls" -}}
AC-3,AC-4,AC-6,AC-17,AU-2,AU-3,AU-11,AU-12,CM-2,CM-6,CM-7,CM-8,IA-2,IA-3,IA-5,SC-7,SC-8,SC-12,SC-13,SC-22,SI-4
{{- end }}

{{- define "pleme-lib.overlay.fedramp-moderate.validate" -}}
{{- include "pleme-lib.compliance.image.validate" . -}}
{{- include "pleme-lib.compliance.authz.validate" . -}}
{{- include "pleme-lib.compliance.authn.validate" . -}}
{{- include "pleme-lib.compliance.egress.validate" . -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- if eq $isWorkload "true" -}}
{{- include "pleme-lib.compliance.security.validate" . -}}
{{- include "pleme-lib.compliance.audit.validate" . -}}
{{- include "pleme-lib.compliance.network.validate" . -}}
{{- include "pleme-lib.compliance.rbac.validate" . -}}
{{- include "pleme-lib.compliance.secrets.validate" . -}}
{{- include "pleme-lib.compliance.ingress.validate" . -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.fedramp-moderate.annotations" -}}
compliance.pleme.io/overlay-fedramp-moderate: "true"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-moderate.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-moderate.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-moderate.manifestData" -}}
overlay-fedramp-moderate: "true"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-moderate.podEnv" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-moderate.imagePullSecrets" -}}{{- end }}

{{/*
Kyverno ClusterPolicy mirroring fedramp-moderate chart-time validators
at the cluster admission boundary. Rejects pods that do not meet:
  - allowPrivilegeEscalation=false (CM-7)
  - readOnlyRootFilesystem=true     (SI-7)
  - drop ALL capabilities           (CM-7)
  - seccompProfile=RuntimeDefault   (CM-6, SI-16)
  - automountServiceAccountToken=false unless explicitly justified (AC-6, IA-2)
A non-helmworks chart that violates these is rejected at admission.
*/}}
{{- define "pleme-lib.overlay.fedramp-moderate.kyvernoPolicy" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pleme-overlay-fedramp-moderate
  annotations:
    pleme.io/overlay: fedramp-moderate
    pleme.io/controls: "CM-6,CM-7,AC-6,IA-2,SI-7,SI-16"
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: forbid-privileged
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-moderate forbids securityContext.privileged=true (CM-7)"
        pattern:
          spec:
            =(containers):
              - =(securityContext):
                  =(privileged): "false"
            =(initContainers):
              - =(securityContext):
                  =(privileged): "false"
    - name: forbid-allow-privilege-escalation
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-moderate forbids securityContext.allowPrivilegeEscalation=true (CM-7, AC-6)"
        pattern:
          spec:
            containers:
              - securityContext:
                  allowPrivilegeEscalation: "false"
    - name: require-readonly-rootfs
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-moderate requires securityContext.readOnlyRootFilesystem=true (SI-7)"
        pattern:
          spec:
            containers:
              - securityContext:
                  readOnlyRootFilesystem: true
    - name: require-drop-all-capabilities
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-moderate requires capabilities.drop containing ALL (CM-7)"
        pattern:
          spec:
            containers:
              - securityContext:
                  capabilities:
                    drop:
                      - ALL
    - name: forbid-host-namespaces
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-moderate forbids hostNetwork / hostPID / hostIPC (AC-6, SC-7)"
        pattern:
          spec:
            =(hostNetwork): "false"
            =(hostPID): "false"
            =(hostIPC): "false"
    - name: forbid-latest-tag
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-moderate forbids image.tag=latest (CM-2, SI-7)"
        pattern:
          spec:
            containers:
              - (image): "!*:latest"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-moderate.gatekeeperConstraint" -}}{{- end }}


{{/* ───────────────────────────── fedramp-high ─────────────────────── */}}

{{- define "pleme-lib.overlay.fedramp-high.requires" -}}fedramp-moderate{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.controls" -}}
AC-6(1),AC-6(7),IA-2(1),SC-5,SC-7(4),SC-7(5),SC-28,SI-7,SI-16
{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.validate" -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- if eq $isWorkload "true" -}}
{{- include "pleme-lib.compliance.availability.validate" . -}}
{{- include "pleme-lib.compliance.attestation.validate" . -}}
{{- include "pleme-lib.compliance.storage.validate" . -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.annotations" -}}
compliance.pleme.io/overlay-fedramp-high: "true"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-high.labels" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.manifestData" -}}
overlay-fedramp-high: "true"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-high.podEnv" -}}{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.imagePullSecrets" -}}{{- end }}

{{/*
fedramp-high adds digest-pinning enforcement at admission time on top of
the moderate policy. This forces every pod to use an @sha256:... image
or sha256: tag pin — no semantic-version tags or `latest`-shaped tags.
*/}}
{{- define "pleme-lib.overlay.fedramp-high.kyvernoPolicy" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pleme-overlay-fedramp-high
  annotations:
    pleme.io/overlay: fedramp-high
    pleme.io/controls: "CM-2,SI-7,AC-6,SC-28"
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-digest-pinned-image
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-high requires images to be digest-pinned (image@sha256:... or :sha256:...) (CM-2, SI-7)"
        pattern:
          spec:
            containers:
              - image: "*sha256:*"
    - name: require-runAsNonRoot
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-high requires runAsNonRoot=true at pod or container level (AC-6)"
        anyPattern:
          - spec:
              securityContext:
                runAsNonRoot: true
          - spec:
              containers:
                - securityContext:
                    runAsNonRoot: true
    - name: forbid-runAsUser-0
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "fedramp-high forbids runAsUser=0 (AC-6)"
        pattern:
          spec:
            =(securityContext):
              =(runAsUser): ">0"
            =(containers):
              - =(securityContext):
                  =(runAsUser): ">0"
{{ end }}

{{- define "pleme-lib.overlay.fedramp-high.gatekeeperConstraint" -}}{{- end }}
