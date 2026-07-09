{{/*
pleme-lib.tieredConfig — declarative shikumi tiered progressive-discovery
config, rendered as *reconciled Helm* (the enjulho way).

A shikumi `TieredConfig` service resolves its effective config through the
sealed progressive fold:

    bare → discovered → prescribed_default → file → env → runtime

The first three tiers are compiled INTO the binary. The last two operator-
overlay tiers — the **file tier** (a mounted YAML the `ConfigStore` discovers
+ hot-reloads) and the **env tier** (a `<PREFIX>_` env-var overlay) — plus the
**discovered tier**'s k8s downward-API reads (`POD_NAMESPACE`/`POD_NAME`) are
exactly the surface a chart owns. This mixin renders that surface from ONE
typed `.Values.config` block, so config becomes version-controlled chart values
+ a reconciled ConfigMap instead of hand-wired env scattered across a
Deployment. Author a chart value; the operator reconciles the config; the
service's `ConfigStore` discovers the file + watches it.

── SECRET BOUNDARY (non-negotiable) ─────────────────────────────────────────
This mixin NEVER renders a secret. Passwords / tokens / API keys
(`PGPASSWORD`, `PANGEA_API_TOKEN`, …) flow through the existing cofre /
`ExternalSecret` / `secretKeyRef` path — never `.Values.config`. Anything a
`config-show` / provenance dump would expose must not land here. The typed
shikumi config structs deliberately exclude secret fields for the same reason;
this mixin mirrors that boundary at the chart layer.

── VALUES SCHEMA (schema-shaped to the service's shikumi TieredConfig) ───────
  config:
    # app name → drives the ConfigMap key (<app>.yaml), the default mount
    # path (/etc/<app>) and the volume name. Defaults to the chart name.
    app: engenho
    # optional explicit ConfigMap name; default "<fullname>-config".
    configMapName: ""

    # ── file tier ── the richer enjulho-native form: the FULL typed config
    # surface, hot-reloadable. The rendered ConfigMap's single data key is
    # "<app>.yaml"; mount it (via .volume + .volumeMount) at mountPath so the
    # ConfigStore's file discovery resolves "<mountPath>/<app>.yaml".
    file:
      enabled: false          # ConfigMap only rendered when true
      fileName: ""            # default "<app>.yaml"
      mountPath: ""           # default "/etc/<app>"
      data: {}               # the typed shikumi surface (file tier) — NO SECRETS
      # ── app-code border (CONFIGURATION-MANAGEMENT §IX) ── a non-Rust service
      # (akeyless = Go/viper) reads a conf whose ON-DISK format is NOT YAML
      # (TOML/ini/properties). `raw` carries that verbatim body — emitted
      # byte-for-byte, no toYaml — so the service's UNCHANGED read-path consumes
      # it. Mutually exclusive with `data` (raw wins). This is where the Go
      # renderer's (camelot-bootstrap RenderConf) main-conf output lands.
      raw: ""                # verbatim file body — NO SECRETS
      # ── secret co-mount ── a viper read-path scans ONE dir for both main.conf
      # AND secret.conf. When `secret.enabled`, the file-tier volume becomes a
      # PROJECTED volume co-locating this ConfigMap (config) with a cofre/ESO
      # Secret (secret.conf) at mountPath. tieredConfig NEVER renders secret
      # CONTENT — it references a Secret ESO produces (the boundary holds).
      secret:
        enabled: false        # co-locate a cofre/ESO Secret at mountPath
        name: ""             # default "<fullname>-secrets"
        optional: true       # missing Secret ⇒ empty (ESO reconciles it in)

    # ── env tier ── simple <PREFIX>_ scalar overrides (name → value).
    env: {}

    # ── discovered tier ── declared in the chart (not assumed): the k8s
    # downward API the service reads at the Discovered tier. Both default on;
    # set false to suppress.
    discovered:
      podNamespace: true      # POD_NAMESPACE ← fieldRef metadata.namespace
      podName: true           # POD_NAME     ← fieldRef metadata.name

── NAMED TEMPLATES ──────────────────────────────────────────────────────────
  pleme-lib.tieredConfig.configMap     full ConfigMap (file tier); no-op unless
                                       config.file.enabled AND config.file.data.
  pleme-lib.tieredConfig.env           env: list-item fragment — env tier +
                                       downward-API discovered tier. nindent
                                       into a container's `env:`.
  pleme-lib.tieredConfig.volume        volumes: list-item fragment for the file
                                       tier ConfigMap. nindent into `volumes:`.
  pleme-lib.tieredConfig.volumeMount   volumeMounts: list-item fragment. nindent
                                       into a container's `volumeMounts:`.
  pleme-lib.tieredConfig.configMapName string helper (ConfigMap name).
  pleme-lib.tieredConfig.volumeName    string helper (volume + mount name).
  pleme-lib.tieredConfig.secretName    string helper (co-mounted cofre/ESO
                                       Secret name; default "<fullname>-secrets").
*/}}

{{/* ── string helpers (shared so name/path never drift across templates) ─── */}}

{{- define "pleme-lib.tieredConfig.app" -}}
{{- $c := .Values.config | default dict -}}
{{- $c.app | default (include "pleme-lib.name" .) -}}
{{- end -}}

{{- define "pleme-lib.tieredConfig.configMapName" -}}
{{- $c := .Values.config | default dict -}}
{{- $c.configMapName | default (printf "%s-config" (include "pleme-lib.fullname" .)) -}}
{{- end -}}

{{- define "pleme-lib.tieredConfig.volumeName" -}}
{{- printf "%s-config" (include "pleme-lib.tieredConfig.app" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pleme-lib.tieredConfig.fileName" -}}
{{- $c := .Values.config | default dict -}}
{{- $file := $c.file | default dict -}}
{{- $file.fileName | default (printf "%s.yaml" (include "pleme-lib.tieredConfig.app" .)) -}}
{{- end -}}

{{- define "pleme-lib.tieredConfig.mountPath" -}}
{{- $c := .Values.config | default dict -}}
{{- $file := $c.file | default dict -}}
{{- $file.mountPath | default (printf "/etc/%s" (include "pleme-lib.tieredConfig.app" .)) -}}
{{- end -}}

{{- define "pleme-lib.tieredConfig.secretName" -}}
{{- $c := .Values.config | default dict -}}
{{- $file := $c.file | default dict -}}
{{- $secret := $file.secret | default dict -}}
{{- $secret.name | default (printf "%s-secrets" (include "pleme-lib.fullname" .)) -}}
{{- end -}}

{{/* ── file tier: the reconciled ConfigMap the ConfigStore discovers ─────── */}}
{{- define "pleme-lib.tieredConfig.configMap" -}}
{{- $c := .Values.config | default dict -}}
{{- $file := $c.file | default dict -}}
{{- if and $file.enabled (or $file.data $file.raw) -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "pleme-lib.tieredConfig.configMapName" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    app.kubernetes.io/component: config
  annotations:
    # The enjulho contract: this ConfigMap IS the service's shikumi file tier.
    pleme.io/config-tier: file
    pleme.io/config-file: {{ include "pleme-lib.tieredConfig.fileName" . | quote }}
    {{- if $file.raw }}
    # app-code border: verbatim (non-YAML) body — the service's read-path format.
    pleme.io/config-format: raw
    {{- end }}
data:
  {{ include "pleme-lib.tieredConfig.fileName" . }}: |
    {{- if $file.raw }}
    {{- $file.raw | nindent 4 }}
    {{- else }}
    {{- toYaml $file.data | nindent 4 }}
    {{- end }}
{{- end -}}
{{- end -}}

{{/* ── env tier + discovered tier: container env: list-item fragment ─────── */}}
{{- define "pleme-lib.tieredConfig.env" -}}
{{- $c := .Values.config | default dict -}}
{{- $disc := $c.discovered | default dict -}}
{{- /* Discovered tier defaults ON; respect an explicit false (`default true`
       would wrongly re-enable it, since false is empty). */ -}}
{{- $podNs := true -}}
{{- if hasKey $disc "podNamespace" }}{{- $podNs = $disc.podNamespace -}}{{- end -}}
{{- $podName := true -}}
{{- if hasKey $disc "podName" }}{{- $podName = $disc.podName -}}{{- end -}}
{{- if $podNs }}
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- end }}
{{- if $podName }}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
{{- end }}
{{- range $k, $v := ($c.env | default dict) }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/* ── file tier plumbing: pod volume list-item fragment ─────────────────── */}}
{{/* Plain configMap volume by default. When config.file.secret.enabled, a
     PROJECTED volume co-locating the file-tier ConfigMap (config) with a
     cofre/ESO Secret (secret.conf) at one mountPath — the app-code border
     idiom (a viper read-path scans one dir). Secret CONTENT is never rendered
     here; only the Secret name is referenced. */}}
{{- define "pleme-lib.tieredConfig.volume" -}}
{{- $c := .Values.config | default dict -}}
{{- $file := $c.file | default dict -}}
{{- $secret := $file.secret | default dict -}}
{{- if and $file.enabled (or $file.data $file.raw) }}
{{- if $secret.enabled }}
- name: {{ include "pleme-lib.tieredConfig.volumeName" . }}
  projected:
    sources:
      - configMap:
          name: {{ include "pleme-lib.tieredConfig.configMapName" . }}
      - secret:
          name: {{ include "pleme-lib.tieredConfig.secretName" . }}
          optional: {{ hasKey $secret "optional" | ternary $secret.optional true }}
{{- else }}
- name: {{ include "pleme-lib.tieredConfig.volumeName" . }}
  configMap:
    name: {{ include "pleme-lib.tieredConfig.configMapName" . }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── file tier plumbing: container volumeMount list-item fragment ──────── */}}
{{- define "pleme-lib.tieredConfig.volumeMount" -}}
{{- $c := .Values.config | default dict -}}
{{- $file := $c.file | default dict -}}
{{- if and $file.enabled (or $file.data $file.raw) }}
- name: {{ include "pleme-lib.tieredConfig.volumeName" . }}
  mountPath: {{ include "pleme-lib.tieredConfig.mountPath" . }}
  readOnly: true
{{- end }}
{{- end -}}
