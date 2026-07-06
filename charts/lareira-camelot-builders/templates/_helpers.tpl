{{/*
lareira-camelot-builders helpers.

The per-arch template files are thin: each gates on arch membership + a toggle,
then `include`s one of the render helpers below with (dict "root" . "arch" "<a>").
This is generation-over-composition (Pillar 12): the render logic is authored
ONCE here and the arch is a parameter — no per-arch duplication.
*/}}

{{- define "lareira-camelot-builders.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "lareira-camelot-builders.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "lareira-camelot-builders.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "lareira-camelot-builders.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}

{{/*
Resolve the effective catalog profile for an arch. The perfClass profile carries
a BASE name (beefy_spot | balanced); the amd64 lane maps beefy_spot →
beefy_spot_amd64 (design §2a/§2h). balanced has no arch variant.
Args: (dict "base" <string> "arch" <string>)
*/}}
{{- define "lareira-camelot-builders.catalogProfile" -}}
{{- $base := .base -}}
{{- $arch := .arch -}}
{{- if and (eq $base "beefy_spot") (eq $arch "amd64") -}}
beefy_spot_amd64
{{- else -}}
{{- $base -}}
{{- end -}}
{{- end -}}

{{/*
infraTemplate — an InfrastructureTemplate CR whose inline Pangea Ruby calls
Pangea::Architectures::CamelotBuilderNodeGroup.build (design §2b). magma renders
it into an aws_autoscaling_group (MixedInstancesAsg) + aws_iam_role + a launch
template pinning the NixOS builder AMI, in one Postgres-atomic apply. The builder
config is passed as compact JSON through a squiggly single-quoted heredoc
(JSON.parse … symbolize_names:true) — the robust, escaping-free path used by the
shipped dashboard-as-code template.
Args: (dict "root" . "arch" "<arm64|amd64>")
*/}}
{{- define "lareira-camelot-builders.infraTemplate" -}}
{{- $root := .root -}}
{{- $arch := .arch -}}
{{- $b := index $root.Values.builders $arch -}}
{{- $ng := $root.Values.nodeGroup -}}
{{- $class := default $root.Values.perfClass $b.perfClass -}}
{{- $prof := index $root.Values.perfClassProfiles $class -}}
{{- $catalogProfile := include "lareira-camelot-builders.catalogProfile" (dict "base" $prof.catalogProfile "arch" $arch) -}}
{{- $odBase := $prof.onDemandBaseCapacity -}}
{{- if eq (toString $odBase) "ceiling" -}}{{- $odBase = $b.ceiling -}}{{- end -}}
{{- $taint := dict "key" $ng.taint.key "value" $ng.taint.value "effect" $ng.taint.effect -}}
{{- $nodeLabel := dict "kubernetes.io/arch" $b.k8sArch "role" $ng.role -}}
{{- $ami := dict "kind" $ng.ami.kind "arch" $arch -}}
{{- $cfg := dict
      "cluster" $root.Values.cluster
      "arch" $arch
      "nix_arch" $b.nixArch
      "role" $ng.role
      "taint" $taint
      "node_label" $nodeLabel
      "catalog" $ng.catalog
      "profile" $catalogProfile
      "substrate" $ng.substrate
      "ami" $ami
      "iam" $ng.iam
      "disk_size_gb" $ng.diskSizeGb
      "min_size" $ng.minSize
      "desired_size" $ng.desiredSize
      "max_size" $b.ceiling
      "perf_class" $class
      "on_demand_base_capacity" $odBase
      "on_demand_percentage_above_base" $prof.onDemandPercentageAboveBase
      "bid_interruption_tolerance" $prof.bidInterruptionTolerance
      "allocation_strategy" $prof.allocationStrategy
      "spot_interruption" $ng.spotInterruption
      "region" $root.Values.region
      "aws_profile" $root.Values.awsProfile
      "cost_sla_cents" $b.costSlaCents
-}}
apiVersion: pangea.pleme.io/v1alpha1
kind: InfrastructureTemplate
metadata:
  name: camelot-builder-{{ $arch }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "lareira-camelot-builders.labels" $root | nindent 4 }}
    pleme.io/pangea-kind: template
    kubernetes.io/arch: {{ $b.k8sArch }}
    role: camelot-builder
spec:
  pangeaNamespace: {{ $root.Values.pangeaNamespace | quote }}
  executor: {{ $root.Values.executor | quote }}
  destroyProtection: {{ $ng.destroyProtection }}
  {{- with $ng.refreshInterval }}
  refreshInterval: {{ . | quote }}
  {{- end }}
  {{- with $ng.settlingPolicy }}
  settlingPolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if $root.Values.aws.credentialsSecret.name }}
  providerCredentials:
    aws:
      secretRef:
        name: {{ $root.Values.aws.credentialsSecret.name }}
        namespace: {{ $root.Values.aws.credentialsSecret.namespace }}
  {{- end }}
  source:
    inline: |
      # camelot nix builder — {{ $arch }} native-metal 100%-spot ASG (design §2b).
      # perfClass={{ $class }} · catalog profile={{ $catalogProfile }} · scale-to-zero
      # (desired 0; breathe owns the count once writeEnabled). No QEMU — native metal.
      template :camelot_builder_{{ $arch }} do
        provider :aws, region: {{ $root.Values.region | quote }}
        self.extend(Pangea::Resources::Aws)
        Pangea::Architectures::CamelotBuilderNodeGroup.build(self,
          JSON.parse(<<~'PANGEA_BUILDER', symbolize_names: true))
{{ $cfg | toJson | indent 10 }}
        PANGEA_BUILDER
      end
{{- end -}}

{{/*
breatheCloudPool — the node-COUNT band (design §2c). SHADOW-FIRST: dryRun +
writeEnabled both default safe-OFF. floor 0 (Trust makes count-0 a real in-band
value); predictive MANDATORY for nodes; pack fill (throughput). Per-arch overrides
asg + ceiling + costSlaCents; the rest of the band shape is shared.
Args: (dict "root" . "arch" "<arm64|amd64>")
*/}}
{{- define "lareira-camelot-builders.breatheCloudPool" -}}
{{- $root := .root -}}
{{- $arch := .arch -}}
{{- $b := index $root.Values.builders $arch -}}
{{- $cp := $root.Values.cloudPool -}}
apiVersion: breathe.pleme.io/v1
kind: BreatheCloudPool
metadata:
  name: camelot-builder-{{ $arch }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "lareira-camelot-builders.labels" $root | nindent 4 }}
    kubernetes.io/arch: {{ $b.k8sArch }}
    role: camelot-builder
spec:
  forma: {{ $cp.forma }}
  target:
    asg: {{ $b.asg }}
    region: {{ $root.Values.region }}
    profile: {{ $root.Values.awsProfile }}
  floor: {{ $cp.floor }}
  ceiling: {{ $b.ceiling }}
  metricMissingPolicy: {{ $cp.metricMissingPolicy }}
  costSlaCents: {{ $b.costSlaCents }}
  reliefLatencySeconds: {{ $cp.reliefLatencySeconds }}
  setpoint: {{ $cp.setpoint }}
  growAbove: {{ $cp.growAbove }}
  shrinkBelow: {{ $cp.shrinkBelow }}
  predictive: {{ $cp.predictive }}
  fillPolicy: {{ $cp.fillPolicy }}
  provider: {{ $cp.provider }}
  signal:
    prometheus: {{ $cp.signal.prometheus }}
  # THE TWO SAFETY GATES — flip LIVE only after shadow-proof (BU10).
  dryRun: {{ $cp.dryRun }}
  writeEnabled: {{ $cp.writeEnabled }}
{{- end -}}

{{/*
interruptionHandler — the scoped retirada drain-ahead seam (design §2f). An
InfrastructureTemplate whose inline Ruby calls Spot::InterruptionHandler.build
SCOPED to this builder ASG (never account-wide — an unscoped rule would fire on
resident-host interruptions and break the gentlemanly-guest posture). OPT-IN.
Args: (dict "root" . "arch" "<arm64|amd64>")
*/}}
{{- define "lareira-camelot-builders.interruptionHandler" -}}
{{- $root := .root -}}
{{- $arch := .arch -}}
{{- $b := index $root.Values.builders $arch -}}
{{- $ih := dict
      "scope" (printf "%s-camelot-builder-%s" $root.Values.cluster $arch)
      "policy" "graceful_terminate"
      "include_rebalance_events" true
-}}
apiVersion: pangea.pleme.io/v1alpha1
kind: InfrastructureTemplate
metadata:
  name: camelot-builder-interruption-{{ $arch }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "lareira-camelot-builders.labels" $root | nindent 4 }}
    pleme.io/pangea-kind: template
    kubernetes.io/arch: {{ $b.k8sArch }}
    role: camelot-builder
spec:
  pangeaNamespace: {{ $root.Values.pangeaNamespace | quote }}
  executor: {{ $root.Values.executor | quote }}
  {{- with $root.Values.nodeGroup.refreshInterval }}
  refreshInterval: {{ . | quote }}
  {{- end }}
  {{- if $root.Values.aws.credentialsSecret.name }}
  providerCredentials:
    aws:
      secretRef:
        name: {{ $root.Values.aws.credentialsSecret.name }}
        namespace: {{ $root.Values.aws.credentialsSecret.namespace }}
  {{- end }}
  source:
    inline: |
      # retirada drain-ahead seam — SCOPED to this builder ASG, never account-wide.
      # Two-tier warning (rebalance-rec earlier than the 2-min notice) → the
      # retirada plan_migration sensor. policy graceful_terminate (+ SNS drain
      # seam, zero external dep). Builders are idempotent + cache-backed: a
      # reclaimed build re-dispatches to a fresh node (a cache hit). (design §2f)
      template :camelot_builder_interruption_{{ $arch }} do
        provider :aws, region: {{ $root.Values.region | quote }}
        self.extend(Pangea::Resources::Aws)
        Pangea::Architectures::Spot::InterruptionHandler.build(self,
          JSON.parse(<<~'PANGEA_IH', symbolize_names: true))
{{ $ih | toJson | indent 10 }}
        PANGEA_IH
      end
{{- end -}}

{{/*
═══════════════════════ Tier B helpers — the super-cache-ci DESTINATION ═══════
Every helper below is only rendered when .Values.tierB.enabled (default false).
INERT until the keystone gates clear (TieredBackend, sui REAPI worker, sui
/metrics). LiveTODO-honest — do not round the destination up to shipped.
*/}}

{{/*
nodeGroupTierB — the EKS-JOINED builder node group (design §2i tierB). Same
CamelotBuilderNodeGroup architecture as Tier A but substrate: eks_managed_node_group.
Args: (dict "root" . "arch" "<arm64|amd64>")
*/}}
{{- define "lareira-camelot-builders.nodeGroupTierB" -}}
{{- $root := .root -}}
{{- $arch := .arch -}}
{{- $b := index $root.Values.builders $arch -}}
{{- $ng := $root.Values.nodeGroup -}}
{{- $tb := $root.Values.tierB.nodeGroup -}}
{{- $class := default $root.Values.perfClass $b.perfClass -}}
{{- $prof := index $root.Values.perfClassProfiles $class -}}
{{- $catalogProfile := include "lareira-camelot-builders.catalogProfile" (dict "base" $prof.catalogProfile "arch" $arch) -}}
{{- $taint := dict "key" $ng.taint.key "value" $ng.taint.value "effect" $ng.taint.effect -}}
{{- $nodeLabel := dict "kubernetes.io/arch" $b.k8sArch "role" $ng.role -}}
{{- $cfg := dict
      "cluster" $root.Values.cluster
      "arch" $arch
      "role" $ng.role
      "taint" $taint
      "node_label" $nodeLabel
      "catalog" $ng.catalog
      "profile" $catalogProfile
      "substrate" "eks_managed_node_group"
      "iam" $ng.iam
      "disk_size_gb" $ng.diskSizeGb
      "min_size" $ng.minSize
      "desired_size" $ng.desiredSize
      "max_size" $tb.ceiling
      "perf_class" $class
      "region" $root.Values.region
      "aws_profile" $root.Values.awsProfile
-}}
apiVersion: pangea.pleme.io/v1alpha1
kind: InfrastructureTemplate
metadata:
  name: camelot-builder-eks-{{ $arch }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "lareira-camelot-builders.labels" $root | nindent 4 }}
    pleme.io/pangea-kind: template
    pleme.io/tier: b
    kubernetes.io/arch: {{ $b.k8sArch }}
    role: camelot-builder
spec:
  pangeaNamespace: {{ $root.Values.pangeaNamespace | quote }}
  executor: {{ $root.Values.executor | quote }}
  source:
    inline: |
      # Tier B (DESTINATION, gated) — EKS-joined camelot builder node group.
      template :camelot_builder_eks_{{ $arch }} do
        provider :aws, region: {{ $root.Values.region | quote }}
        self.extend(Pangea::Resources::Aws)
        Pangea::Architectures::CamelotBuilderNodeGroup.build(self,
          JSON.parse(<<~'PANGEA_EKS', symbolize_names: true))
{{ $cfg | toJson | indent 10 }}
        PANGEA_EKS
      end
{{- end -}}

{{/*
arcRunnerSet — the ARC AutoscalingRunnerSet, minRunners:0 → pods scale 0→N on
queued jobs (design §2e). Field-disjoint from the node count.
Args: (dict "root" . "arch" "<arm64|amd64>")
*/}}
{{- define "lareira-camelot-builders.arcRunnerSet" -}}
{{- $root := .root -}}
{{- $arch := .arch -}}
{{- $b := index $root.Values.builders $arch -}}
{{- $arc := $root.Values.tierB.arc -}}
apiVersion: actions.github.com/v1alpha1
kind: AutoscalingRunnerSet
metadata:
  name: camelot-builder-{{ $arch }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "lareira-camelot-builders.labels" $root | nindent 4 }}
    pleme.io/tier: b
    kubernetes.io/arch: {{ $b.k8sArch }}
spec:
  githubConfigUrl: {{ $arc.githubConfigUrl | quote }}
  {{- with $arc.githubConfigSecret }}
  githubConfigSecret: {{ . | quote }}
  {{- end }}
  minRunners: {{ $arc.minRunners }}
  maxRunners: {{ $arc.maxRunners }}
  template:
    spec:
      nodeSelector:
        role: camelot-builder
        kubernetes.io/arch: {{ $b.k8sArch }}
      tolerations:
        - key: camelot-builder
          value: "true"
          effect: NoSchedule
      containers:
        - name: runner
          image: ghcr.io/actions/actions-runner:latest
          command: ["/home/runner/run.sh"]
{{- end -}}

{{/*
replicaBand — the runner-replica axis (Topology::NonPersistent, shadow-first)
(design §2e). Preemptive, topology-aware; SpotScaleOut fires on reclaim.
Args: (dict "root" . "arch" "<arm64|amd64>")
*/}}
{{- define "lareira-camelot-builders.replicaBand" -}}
{{- $root := .root -}}
{{- $arch := .arch -}}
{{- $b := index $root.Values.builders $arch -}}
{{- $rb := $root.Values.tierB.replicaBand -}}
apiVersion: breathe.pleme.io/v1
kind: ReplicaBand
metadata:
  name: camelot-builder-runners-{{ $arch }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "lareira-camelot-builders.labels" $root | nindent 4 }}
    pleme.io/tier: b
    kubernetes.io/arch: {{ $b.k8sArch }}
spec:
  targetRef:
    kind: AutoscalingRunnerSet
    name: camelot-builder-{{ $arch }}
  topology:
    kind: {{ $rb.topology }}
  signal:
    prometheus: {{ $rb.signal.prometheus }}
  floor: {{ $rb.floor }}
  ceiling: {{ $rb.ceiling }}
  dryRun: {{ $rb.dryRun }}
{{- end -}}

{{/*
memoryBand — the RAMDISK carve (P0-#2, design §2d): couple the pod memory limit
AND the emptyDir{Memory} sizeLimit so `limit ≥ tmpfs + build-RSS headroom` holds
by construction; spill to a disk-backed emptyDir when the RAM medium fills.
Shadow-first. Args: (dict "root" . "arch" "<arm64|amd64>")
*/}}
{{- define "lareira-camelot-builders.memoryBand" -}}
{{- $root := .root -}}
{{- $arch := .arch -}}
{{- $b := index $root.Values.builders $arch -}}
{{- $mb := $root.Values.tierB.memoryBand -}}
apiVersion: breathe.pleme.io/v1
kind: MemoryBand
metadata:
  name: camelot-builder-ramdisk-{{ $arch }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "lareira-camelot-builders.labels" $root | nindent 4 }}
    pleme.io/tier: b
    kubernetes.io/arch: {{ $b.k8sArch }}
spec:
  targetRef:
    kind: Deployment
    name: sui-builder-{{ $arch }}
  couple:
    emptyDirMedium: Memory
    mountPath: {{ $mb.mountPath }}
  setpoint: {{ $mb.setpoint }}
  cooldownSeconds: {{ $mb.cooldownSeconds }}
  maxStalenessSeconds: {{ $mb.maxStalenessSeconds }}
  spillTo:
    emptyDir: {}
  dryRun: {{ $mb.dryRun }}
{{- end -}}

