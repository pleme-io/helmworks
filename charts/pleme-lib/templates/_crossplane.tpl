{{/*
pleme-lib: Crossplane substrate primitives — the full v1+v2 vocabulary, rendered from
values maps so one chart declares an entire Crossplane substrate without hand-writing a
template file per resource.

Package + runtime layer (pkg.crossplane.io):
  - crossplaneProvider            Provider (+ folded DeploymentRuntimeConfig on irsaRoleArn)
  - crossplaneProviderConfig      ProviderConfig (per-family apiVersion)
  - crossplaneFunction            Function
  - crossplaneConfiguration       Configuration (XRD+Composition bundle package)
  - crossplaneDeploymentRuntimeConfig   standalone DeploymentRuntimeConfig
Composition layer (apiextensions.crossplane.io):
  - crossplaneCompositeResourceDefinition (alias crossplaneXRD)  XRD (v2 default; /v1 toggle)
  - crossplaneComposition         Composition (function-pipeline only)
  - crossplaneEnvironmentConfig   EnvironmentConfig (cluster-scoped data bag)
Protection (protection.crossplane.io):
  - crossplaneUsage               Usage (namespaced) | ClusterUsage (cluster), via `cluster:`
Operations (ops.crossplane.io/v1alpha1 — ALPHA, feature-gated, opt-in):
  - crossplaneOperation / crossplaneCronOperation / crossplaneWatchOperation

SCOPE: most kinds are cluster-scoped (NO metadata.namespace — structural template is
_karpenter.tpl, not _externalsecret.tpl). The ONE exception is `Usage` (namespaced): it
borrows the ExternalSecret namespace idiom on its non-`cluster:` branch. The XRD itself is
always cluster-scoped; its spec.scope controls the scope of the GENERATED composite.

Each helper is a no-op when its map is empty/absent, composes pleme-lib.labels +
crossplaneAnnotations (engine-neutral), and fail()s on missing required fields. The
provider loop NEVER derives a provider-family-aws CR (Crossplane auto-resolves it; an
explicit family CR is a duplicate-source lock).

Consumers structure values as (package layer shown; see each define's doc for the rest):

  crossplane:
    providers:
      provider-aws-rds:                  # map key → Provider/<key> (metadata.name verbatim)
        # Package: a full `package:` string WINS; otherwise assembled from parts.
        registry: xpkg.upbound.io/upbound
        name: provider-aws-rds
        version: "2.5.3"                  # versionPrefix (default "v") is prepended unless
                                          # the version already carries it
        # package: xpkg.upbound.io/upbound/provider-aws-rds:v2.5.3   # full override
        irsaRoleArn: ""                   # non-empty → ALSO emit a paired DeploymentRuntimeConfig
                                          # (same name) + wire spec.runtimeConfigRef
        # packagePullPolicy / revisionActivationPolicy / ignoreCrossplaneConstraints  # passthrough
        # apiVersion: pkg.crossplane.io/v1   # optional override
        # serviceAccountName: <name>     # optional, on the paired DRC's ServiceAccount
        # annotations: { ... }           # free-form metadata.annotations passthrough
    providerConfigs:
      aws:                               # logical handle (NOT the CR name)
        apiVersion: aws.upbound.io/v1beta1   # REQUIRED — varies per provider family
        name: default                    # CR name; default "default"
        credentialsSource: IRSA          # or InjectedIdentity; ignored when `spec:` is set
        # spec: { ... }                  # full escape hatch (wins over credentialsSource)
    functions:
      function-kcl:
        registry: xpkg.upbound.io/crossplane-contrib
        name: function-kcl
        version: "0.11.0"
*/}}

{{/*
pleme-lib.crossplaneAnnotations — merge typed attestation annotations with a per-entry
free-form `annotations` passthrough. Arg: a 2-element list [ $root, $spec ] (attestation
needs the ROOT ctx for .Values.attestation; the passthrough needs the per-entry spec).
Returns a (possibly empty) "key: value" block; the caller guards it with `with`.
*/}}
{{- define "pleme-lib.crossplaneAnnotations" -}}
{{- $ctx := index . 0 -}}
{{- $spec := index . 1 -}}
{{- $parts := list -}}
{{- $attest := include "pleme-lib.attestationAnnotations" $ctx | trim -}}
{{- if $attest -}}{{- $parts = append $parts $attest -}}{{- end -}}
{{- if $spec.annotations -}}{{- $parts = append $parts (toYaml $spec.annotations | trim) -}}{{- end -}}
{{- join "\n" $parts -}}
{{- end -}}

{{/*
pleme-lib.crossplanePackage — resolve a package string for a provider/function entry.
Arg: a dict { name, spec }. A full `package:` wins; otherwise assemble registry/name:vVERSION,
prepending versionPrefix (default "v") only when the version does not already carry it.
fail()s loudly when neither a full package nor all of {registry,name,version} is satisfiable,
so a half-specified entry never renders a silently-invalid (ImagePullBackOff) package.
*/}}
{{- define "pleme-lib.crossplanePackage" -}}
{{- $name := .name -}}
{{- $spec := .spec -}}
{{- if $spec.package -}}
{{- $spec.package -}}
{{- else -}}
{{- $ver := toString ($spec.version | default "") -}}
{{- $vp := default "v" $spec.versionPrefix -}}
{{- if and $ver (not (hasPrefix $vp $ver)) -}}{{- $ver = printf "%s%s" $vp $ver -}}{{- end -}}
{{- if and $spec.registry $spec.name $ver -}}
{{- printf "%s/%s:%s" $spec.registry $spec.name $ver -}}
{{- else -}}
{{- fail (printf "pleme-lib crossplane %q: set either 'package:' or all of {registry,name,version}" $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
pleme-lib.crossplaneProvider — one Provider per .Values.crossplane.providers entry,
plus a paired DeploymentRuntimeConfig (same name) wiring an IRSA ServiceAccount when the
entry sets a non-empty irsaRoleArn.
*/}}
{{- define "pleme-lib.crossplaneProvider" -}}
{{- range $name, $spec := (.Values.crossplane).providers }}
---
apiVersion: {{ $spec.apiVersion | default "pkg.crossplane.io/v1" }}
kind: Provider
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  package: {{ include "pleme-lib.crossplanePackage" (dict "name" $name "spec" $spec) | quote }}
  {{- with $spec.packagePullPolicy }}
  packagePullPolicy: {{ . }}
  {{- end }}
  {{- with $spec.revisionActivationPolicy }}
  revisionActivationPolicy: {{ . }}
  {{- end }}
  {{- if hasKey $spec "ignoreCrossplaneConstraints" }}
  ignoreCrossplaneConstraints: {{ $spec.ignoreCrossplaneConstraints }}
  {{- end }}
  {{- if not (empty $spec.irsaRoleArn) }}
  runtimeConfigRef:
    name: {{ $name }}
  {{- end }}
{{- if not (empty $spec.irsaRoleArn) }}
---
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  serviceAccountTemplate:
    metadata:
      {{- with $spec.serviceAccountName }}
      name: {{ . }}
      {{- end }}
      annotations:
        eks.amazonaws.com/role-arn: {{ $spec.irsaRoleArn | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.crossplaneProviderConfig — one ProviderConfig (namespaced) or ClusterProviderConfig
(cluster-scoped) per .Values.crossplane.providerConfigs entry. apiVersion is REQUIRED (varies
by family). Common case is a credentials.source; a full `spec:` escape hatch overrides it.

SCOPE (Crossplane v2): ProviderConfig is NAMESPACED in v2 — a namespaced managed resource
references a ProviderConfig in its own namespace. A cluster-scoped one (referenced by
namespaced MRs across namespaces, the common substrate case) is `ClusterProviderConfig`.
Toggle with `cluster: true` (mirrors the crossplaneUsage / ClusterUsage split). Default
(false) emits `ProviderConfig`; supply `namespace:` to place it (else the entry is
namespace-less — valid for a v1/LegacyCluster control plane where ProviderConfig is
cluster-scoped, preserving backward-compat for pre-v2 consumers).
*/}}
{{- define "pleme-lib.crossplaneProviderConfig" -}}
{{- range $name, $spec := (.Values.crossplane).providerConfigs }}
{{- if not $spec.apiVersion }}{{- fail (printf "pleme-lib crossplaneProviderConfig %q: apiVersion is required (varies by provider family, e.g. aws.upbound.io/v1beta1)" $name) }}{{- end }}
{{- $isCluster := $spec.cluster | default false }}
---
apiVersion: {{ $spec.apiVersion }}
kind: {{ if $isCluster }}ClusterProviderConfig{{ else }}ProviderConfig{{ end }}
metadata:
  name: {{ $spec.name | default "default" }}
  {{- if and (not $isCluster) $spec.namespace }}
  namespace: {{ $spec.namespace }}
  {{- end }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  {{- if $spec.spec }}
  {{- tpl (toYaml $spec.spec) $ | nindent 2 }}
  {{- else }}
  credentials:
    source: {{ $spec.credentialsSource | default "InjectedIdentity" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.crossplaneFunction — one Function per .Values.crossplane.functions entry.
*/}}
{{- define "pleme-lib.crossplaneFunction" -}}
{{- range $name, $spec := (.Values.crossplane).functions }}
---
apiVersion: {{ $spec.apiVersion | default "pkg.crossplane.io/v1beta1" }}
kind: Function
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  package: {{ include "pleme-lib.crossplanePackage" (dict "name" $name "spec" $spec) | quote }}
  {{- with $spec.packagePullPolicy }}
  packagePullPolicy: {{ . }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.crossplaneManagedResourceActivationPolicy (alias: crossplaneMRAP) — one
ManagedResourceActivationPolicy per .Values.crossplane.managedResourceActivationPolicies
entry. THE SCOPE-BY-DEFAULT primitive (Crossplane v2 / Upbound provider-family v2).

Why this exists: a v2 service provider installs its ManagedResourceDefinitions (MRDs)
INACTIVE by default; an MRAP's `spec.activate` glob-list is what flips the needed ones
Active (their CRD becomes served). Activating ONLY what a workload uses is the
feature-neutral lever against the apiserver /openapi/v2 full-merge cost — deactivated MRs
keep zero CRD schema in the aggregated OpenAPI doc, and re-activating one is a one-line
glob edit (no data loss, fully reversible). This is the upstream-documented way to run the
big AWS providers at scale (vs. installing 185 CRDs to use 1).

  crossplane:
    managedResourceActivationPolicies:
      minimal:
        activate:
          - instances.rds.aws.upbound.io        # exact MR name — one kind
          - "*.s3.aws.upbound.io"               # glob — a whole service's MRs
        # apiVersion: apiextensions.crossplane.io/v2alpha1   # OVERRIDE per installed crossplane

VERIFY-POINT: confirm the apiVersion + that MRAP/MRD is exposed by the installed provider
package channel before applying — `kubectl api-resources | grep -i
managedresourceactivationpolicy`. The default below targets the v2alpha1 surface; override
`apiVersion:` if the cluster serves a different one. fail()s on an empty activate list so a
policy never silently activates nothing (which would deactivate the whole provider).
*/}}
{{- define "pleme-lib.crossplaneManagedResourceActivationPolicy" -}}
{{- range $name, $spec := (.Values.crossplane).managedResourceActivationPolicies }}
{{- if not $spec.activate }}{{- fail (printf "pleme-lib crossplaneMRAP %q: spec.activate (a non-empty glob list of MR names to keep Active) is required — an empty list would deactivate every managed resource" $name) }}{{- end }}
---
apiVersion: {{ $spec.apiVersion | default "apiextensions.crossplane.io/v2alpha1" }}
kind: ManagedResourceActivationPolicy
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  activate:
    {{- range $spec.activate }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
{{- end }}

{{- define "pleme-lib.crossplaneMRAP" -}}
{{- include "pleme-lib.crossplaneManagedResourceActivationPolicy" . }}
{{- end -}}

{{/*
pleme-lib.crossplaneConfiguration — one Configuration package per
.Values.crossplane.configurations entry. Same package layer as Provider/Function
(pkg.crossplane.io), but the install kind is `Configuration` (an XRD+Composition
bundle). apiVersion defaults to the stable pkg.crossplane.io/v1.
*/}}
{{- define "pleme-lib.crossplaneConfiguration" -}}
{{- range $name, $spec := (.Values.crossplane).configurations }}
---
apiVersion: {{ $spec.apiVersion | default "pkg.crossplane.io/v1" }}
kind: Configuration
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  package: {{ include "pleme-lib.crossplanePackage" (dict "name" $name "spec" $spec) | quote }}
  {{- with $spec.packagePullPolicy }}
  packagePullPolicy: {{ . }}
  {{- end }}
  {{- with $spec.packagePullSecrets }}
  packagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.revisionActivationPolicy }}
  revisionActivationPolicy: {{ . }}
  {{- end }}
  {{- with $spec.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  {{- if hasKey $spec "ignoreCrossplaneConstraints" }}
  ignoreCrossplaneConstraints: {{ $spec.ignoreCrossplaneConstraints }}
  {{- end }}
  {{- if hasKey $spec "skipDependencyResolution" }}
  skipDependencyResolution: {{ $spec.skipDependencyResolution }}
  {{- end }}
  {{- with $spec.commonLabels }}
  commonLabels:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.crossplaneCompositeResourceDefinition (alias: crossplaneXRD) — one XRD per
.Values.crossplane.compositeResourceDefinitions entry. TYPED where it's load-bearing
(group / names / versions shape + the apiVersion v2/v1 toggle), ESCAPE-HATCH for the
openAPIV3Schema (passed through verbatim — never hand-model OpenAPI). The two v1-only
fields (claimNames, connectionSecretKeys) are fail()-guarded invariants per the GEN
TYPED-SPEC CONTRACT: conditional emission rules are asserted, not commented.

The XRD itself is always cluster-scoped; spec.scope (v2) controls the scope of the
GENERATED composite resource (Namespaced default | Cluster | LegacyCluster), not the XRD.
*/}}
{{- define "pleme-lib.crossplaneCompositeResourceDefinition" -}}
{{- range $name, $spec := (.Values.crossplane).compositeResourceDefinitions }}
{{- $apiVersion := $spec.apiVersion | default "apiextensions.crossplane.io/v2" }}
{{- $isV2 := eq $apiVersion "apiextensions.crossplane.io/v2" }}
{{- if not $spec.group }}{{- fail (printf "pleme-lib crossplaneXRD %q: spec.group is required" $name) }}{{- end }}
{{- if not (($spec.names).kind) }}{{- fail (printf "pleme-lib crossplaneXRD %q: spec.names.kind is required" $name) }}{{- end }}
{{- if not $spec.versions }}{{- fail (printf "pleme-lib crossplaneXRD %q: spec.versions is required" $name) }}{{- end }}
{{- $refCount := 0 }}
{{- range $v := $spec.versions }}{{- if $v.referenceable }}{{- $refCount = add1 $refCount }}{{- end }}{{- end }}
{{- if ne $refCount 1 }}{{- fail (printf "pleme-lib crossplaneXRD %q: exactly one version must be referenceable:true (found %d)" $name $refCount) }}{{- end }}
{{- if and $spec.claimNames (and $isV2 (ne ($spec.scope | default "Namespaced") "LegacyCluster")) }}{{- fail (printf "pleme-lib crossplaneXRD %q: claimNames is only valid under apiextensions.crossplane.io/v1 or scope: LegacyCluster" $name) }}{{- end }}
{{- if and $spec.connectionSecretKeys $isV2 }}{{- fail (printf "pleme-lib crossplaneXRD %q: connectionSecretKeys is removed in v2 (recompose your own Secret)" $name) }}{{- end }}
---
apiVersion: {{ $apiVersion }}
kind: CompositeResourceDefinition
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  group: {{ $spec.group }}
  names:
    {{- toYaml $spec.names | nindent 4 }}
  {{- if and $isV2 $spec.scope }}
  scope: {{ $spec.scope }}
  {{- end }}
  {{- if and (not $isV2) $spec.claimNames }}
  claimNames:
    {{- toYaml $spec.claimNames | nindent 4 }}
  {{- end }}
  {{- with $spec.defaultCompositionRef }}
  defaultCompositionRef:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.defaultCompositionUpdatePolicy }}
  defaultCompositionUpdatePolicy: {{ . }}
  {{- end }}
  {{- with $spec.enforcedCompositionRef }}
  enforcedCompositionRef:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.conversion }}
  conversion:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.metadata }}
  metadata:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if and (not $isV2) $spec.connectionSecretKeys }}
  connectionSecretKeys:
    {{- toYaml $spec.connectionSecretKeys | nindent 4 }}
  {{- end }}
  versions:
    {{- tpl (toYaml $spec.versions) $ | nindent 4 }}
{{- end }}
{{- end }}

{{- define "pleme-lib.crossplaneXRD" -}}
{{- include "pleme-lib.crossplaneCompositeResourceDefinition" . }}
{{- end -}}

{{/*
pleme-lib.crossplaneComposition — one Composition per .Values.crossplane.compositions
entry. TYPED compositeTypeRef + mode guard (v2 is Pipeline-only; native patch-and-transform
was removed), ESCAPE-HATCH on the pipeline list (arbitrary N steps, opaque per-step input —
NO engine assumption baked in). apiVersion stays apiextensions.crossplane.io/v1 — there is
NO v2 Composition kind; only the XRD bumps to v2.
*/}}
{{- define "pleme-lib.crossplaneComposition" -}}
{{- range $name, $spec := (.Values.crossplane).compositions }}
{{- if not $spec.compositeTypeRef }}{{- fail (printf "pleme-lib crossplaneComposition %q: spec.compositeTypeRef is required" $name) }}{{- end }}
{{- if not $spec.pipeline }}{{- fail (printf "pleme-lib crossplaneComposition %q: spec.pipeline is required (v2 is function-pipeline only)" $name) }}{{- end }}
{{- $mode := $spec.mode | default "Pipeline" }}
{{- if ne $mode "Pipeline" }}{{- fail (printf "pleme-lib crossplaneComposition %q: mode %q unsupported — v2 is Pipeline-only (native patch-and-transform removed)" $name $mode) }}{{- end }}
---
apiVersion: {{ $spec.apiVersion | default "apiextensions.crossplane.io/v1" }}
kind: Composition
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  compositeTypeRef:
    {{- toYaml $spec.compositeTypeRef | nindent 4 }}
  mode: {{ $mode }}
  {{- with $spec.writeConnectionSecretsToNamespace }}
  writeConnectionSecretsToNamespace: {{ . }}
  {{- end }}
  pipeline:
    {{- tpl (toYaml $spec.pipeline) $ | nindent 4 }}
{{- end }}
{{- end }}

{{/*
pleme-lib.crossplaneEnvironmentConfig — one EnvironmentConfig per
.Values.crossplane.environmentConfigs entry. A cluster-scoped data bag that
Compositions read at render time (via function-environment-configs). `data` is
top-level (not under spec) and passed through verbatim. Selectable `labels` merge
onto metadata.labels so a Composition can matchLabels-select.
*/}}
{{- define "pleme-lib.crossplaneEnvironmentConfig" -}}
{{- range $name, $spec := (.Values.crossplane).environmentConfigs }}
{{- if not (hasKey $spec "data") }}{{- fail (printf "pleme-lib crossplaneEnvironmentConfig %q: spec.data is required" $name) }}{{- end }}
---
apiVersion: {{ $spec.apiVersion | default "apiextensions.crossplane.io/v1beta1" }}
kind: EnvironmentConfig
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
    {{- with $spec.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
data:
  {{- tpl (toYaml $spec.data) $ | nindent 2 }}
{{- end }}
{{- end }}

{{/*
pleme-lib.crossplaneDeploymentRuntimeConfig — standalone DeploymentRuntimeConfig per
.Values.crossplane.deploymentRuntimeConfigs entry. Generalizes the IRSA slice the
Provider helper folds inline, for DRCs that aren't 1:1 with a Provider (tuning
replicas / SA attach / full runtime overrides). Typed shortcuts (irsaRoleArn,
serviceAccountName, replicas) compose into the three runtime templates; full
escape-hatch passthroughs (serviceAccountTemplate / deploymentTemplate /
serviceTemplate) win on overlap. An empty spec is a VALID CR — no fail().

Footgun (cannot prevent via template): serviceAccountTemplate.metadata.name TAKES
OWNERSHIP of the SA; deploymentTemplate...serviceAccountName merely ATTACHES. The
shortcuts steer to the safe path (irsaRoleArn -> annotations only; serviceAccountName
-> attach).
*/}}
{{- define "pleme-lib.crossplaneDeploymentRuntimeConfig" -}}
{{- range $name, $spec := (.Values.crossplane).deploymentRuntimeConfigs }}
---
apiVersion: {{ $spec.apiVersion | default "pkg.crossplane.io/v1beta1" }}
kind: DeploymentRuntimeConfig
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  {{- if $spec.serviceAccountTemplate }}
  serviceAccountTemplate:
    {{- tpl (toYaml $spec.serviceAccountTemplate) $ | nindent 4 }}
  {{- else if not (empty $spec.irsaRoleArn) }}
  serviceAccountTemplate:
    metadata:
      {{- with $spec.serviceAccountName }}
      name: {{ . }}
      {{- end }}
      annotations:
        eks.amazonaws.com/role-arn: {{ $spec.irsaRoleArn | quote }}
  {{- end }}
  {{- if $spec.deploymentTemplate }}
  deploymentTemplate:
    {{- tpl (toYaml $spec.deploymentTemplate) $ | nindent 4 }}
  {{- else if or $spec.replicas $spec.serviceAccountName }}
  deploymentTemplate:
    spec:
      {{- with $spec.replicas }}
      replicas: {{ . }}
      {{- end }}
      {{- with $spec.serviceAccountName }}
      template:
        spec:
          serviceAccountName: {{ . }}
      {{- end }}
  {{- end }}
  {{- with $spec.serviceTemplate }}
  serviceTemplate:
    {{- tpl (toYaml .) $ | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.crossplaneUsage — one Usage (namespaced) or ClusterUsage (cluster-scoped)
per .Values.crossplane.usages entry. This is the FIRST namespaced crossplane-family CR
in pleme-lib; the namespaced branch borrows the ExternalSecret namespace idiom
(`namespace: {{ $spec.namespace | default (include "pleme-lib.namespace" $) }}`),
not the cluster-only crossplane idiom. Enforces the of + (by|reason) one-of invariant.
*/}}
{{- define "pleme-lib.crossplaneUsage" -}}
{{- range $name, $spec := (.Values.crossplane).usages }}
{{- if not $spec.of }}{{- fail (printf "pleme-lib crossplaneUsage %q: spec.of is required" $name) }}{{- end }}
{{- if and (not $spec.by) (not $spec.reason) }}{{- fail (printf "pleme-lib crossplaneUsage %q: at least one of spec.by or spec.reason is required" $name) }}{{- end }}
{{- $isCluster := $spec.cluster | default false }}
---
apiVersion: {{ $spec.apiVersion | default "protection.crossplane.io/v1beta1" }}
kind: {{ if $isCluster }}ClusterUsage{{ else }}Usage{{ end }}
metadata:
  name: {{ $name }}
  {{- if not $isCluster }}
  namespace: {{ $spec.namespace | default (include "pleme-lib.namespace" $) }}
  {{- end }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  of:
    {{- toYaml $spec.of | nindent 4 }}
  {{- with $spec.by }}
  by:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.reason }}
  reason: {{ . | quote }}
  {{- end }}
  {{- if hasKey $spec "replayDeletion" }}
  replayDeletion: {{ $spec.replayDeletion }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
─────────────────────────────────────────────────────────────────────────────
Crossplane v2 Operations (ops.crossplane.io/v1alpha1) — ALPHA, opt-in.

These three kinds are ALPHA and FEATURE-GATED on the control plane:
  - Operation / CronOperation require --enable-operations
  - WatchOperation requires --enable-watch-operations
Without the gate the CRDs are absent and these resources are rejected AT APPLY
TIME (not render time — helm-unittest passes, the cluster rejects). They are
NOT wired into any default example; a consumer opts in by populating the map on
a control plane that has the gates enabled. Pipeline steps reuse the same
opaque-passthrough shape as crossplaneComposition (engine-neutral).
─────────────────────────────────────────────────────────────────────────────
*/}}

{{/* pleme-lib.crossplaneOperation — run-once function pipeline (Job-like). */}}
{{- define "pleme-lib.crossplaneOperation" -}}
{{- range $name, $spec := (.Values.crossplane).operations }}
{{- if not $spec.pipeline }}{{- fail (printf "pleme-lib crossplaneOperation %q: spec.pipeline is required" $name) }}{{- end }}
{{- $mode := $spec.mode | default "Pipeline" }}
{{- if ne $mode "Pipeline" }}{{- fail (printf "pleme-lib crossplaneOperation %q: mode must be Pipeline" $name) }}{{- end }}
---
apiVersion: {{ $spec.apiVersion | default "ops.crossplane.io/v1alpha1" }}
kind: Operation
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  mode: {{ $mode }}
  {{- with $spec.retryLimit }}
  retryLimit: {{ . }}
  {{- end }}
  pipeline:
    {{- tpl (toYaml $spec.pipeline) $ | nindent 4 }}
{{- end }}
{{- end }}

{{/* pleme-lib.crossplaneCronOperation — scheduled Operation (cron). */}}
{{- define "pleme-lib.crossplaneCronOperation" -}}
{{- range $name, $spec := (.Values.crossplane).cronOperations }}
{{- if not $spec.schedule }}{{- fail (printf "pleme-lib crossplaneCronOperation %q: spec.schedule is required" $name) }}{{- end }}
{{- if not $spec.operationTemplate }}{{- fail (printf "pleme-lib crossplaneCronOperation %q: spec.operationTemplate is required" $name) }}{{- end }}
---
apiVersion: {{ $spec.apiVersion | default "ops.crossplane.io/v1alpha1" }}
kind: CronOperation
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  schedule: {{ $spec.schedule | quote }}
  {{- with $spec.concurrencyPolicy }}
  concurrencyPolicy: {{ . }}
  {{- end }}
  {{- with $spec.startingDeadlineSeconds }}
  startingDeadlineSeconds: {{ . }}
  {{- end }}
  {{- with $spec.successfulHistoryLimit }}
  successfulHistoryLimit: {{ . }}
  {{- end }}
  {{- with $spec.failedHistoryLimit }}
  failedHistoryLimit: {{ . }}
  {{- end }}
  operationTemplate:
    {{- tpl (toYaml $spec.operationTemplate) $ | nindent 4 }}
{{- end }}
{{- end }}

{{/* pleme-lib.crossplaneWatchOperation — event-triggered Operation (on a watched resource). */}}
{{- define "pleme-lib.crossplaneWatchOperation" -}}
{{- range $name, $spec := (.Values.crossplane).watchOperations }}
{{- if not $spec.watch }}{{- fail (printf "pleme-lib crossplaneWatchOperation %q: spec.watch is required" $name) }}{{- end }}
{{- if not $spec.operationTemplate }}{{- fail (printf "pleme-lib crossplaneWatchOperation %q: spec.operationTemplate is required" $name) }}{{- end }}
---
apiVersion: {{ $spec.apiVersion | default "ops.crossplane.io/v1alpha1" }}
kind: WatchOperation
metadata:
  name: {{ $name }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.crossplaneAnnotations" (list $ $spec)) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  watch:
    {{- toYaml $spec.watch | nindent 4 }}
  {{- with $spec.concurrencyPolicy }}
  concurrencyPolicy: {{ . }}
  {{- end }}
  {{- with $spec.successfulHistoryLimit }}
  successfulHistoryLimit: {{ . }}
  {{- end }}
  {{- with $spec.failedHistoryLimit }}
  failedHistoryLimit: {{ . }}
  {{- end }}
  operationTemplate:
    {{- tpl (toYaml $spec.operationTemplate) $ | nindent 4 }}
{{- end }}
{{- end }}
