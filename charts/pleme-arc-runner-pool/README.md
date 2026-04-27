# pleme-arc-runner-pool

Composition chart for a [GitHub Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) runner pool. Bundles the surrounding Kubernetes / cloud primitives that any pool needs:

- **ServiceAccount** with IRSA annotation (or GCP Workload Identity / Azure AD Workload Identity equivalent)
- **Namespace-scoped Role + RoleBinding** for whatever in-cluster verbs the runner workloads need
- **Dedicated Karpenter NodePool** (per-pool isolation: runner pods schedule onto pool-specific nodes via taint + toleration; idle cost = $0 since no nodes provision until a runner pod goes pending)
- **AutoscalingRunnerSet** registering the pool with GitHub (via the upstream `gha-runner-scale-set` chart as a Helm dependency)

## Why a composition chart

Every runner pool needs the same set of resources. Without a chart, every consumer (per-tenant, per-workflow, per-cluster) reinvents the IRSA SA + namespace RBAC + NodePool wiring inline in Terraform / values files. With this chart, a consumer declares one Helm release per pool — pool name, IAM role ARN, RBAC verbs, NodePool taints/limits — and gets a working pool.

The chart composes pleme-lib helpers (`serviceaccount`, `namespacedRBAC`, `karpenterNodePool`, `karpenterEC2NodeClass`) on top of the upstream `gha-runner-scale-set` chart.

## Installation

### Via FluxCD HelmRelease (preferred)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: example-runner-pool
  namespace: flux-system
spec:
  targetNamespace: example-runner-pool
  install:
    createNamespace: true
  chart:
    spec:
      chart: pleme-arc-runner-pool
      version: "~0.1.0"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
  values:
    serviceAccount:
      name: example-runner-sa
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/example-runner-role"
    rbac:
      roles:
        runner:
          rules:
            - apiGroups: [""]
              resources: ["pods", "namespaces"]
              verbs: ["get", "list", "watch"]
          subjects:
            - kind: ServiceAccount
              name: example-runner-sa
    karpenter:
      nodePools:
        example-runner-pool:
          weight: 50
          limits: { cpu: "100", memory: "400Gi" }
          disruption:
            consolidationPolicy: WhenEmpty
            consolidateAfter: 1m
          template:
            metadata:
              labels:
                runner-pool: example-runner-pool
            spec:
              taints:
                - { key: arc-runner, value: "true", effect: NoSchedule }
              nodeClassRef:
                group: karpenter.k8s.aws
                kind: EC2NodeClass
                name: general
              expireAfter: 8h
              terminationGracePeriod: 10m
              requirements:
                - { key: kubernetes.io/arch, operator: In, values: ["amd64"] }
                - { key: kubernetes.io/os, operator: In, values: ["linux"] }
                - { key: karpenter.sh/capacity-type, operator: In, values: ["spot", "on-demand"] }
                - { key: karpenter.k8s.aws/instance-category, operator: In, values: ["c", "m"] }
                - { key: karpenter.k8s.aws/instance-size, operator: In, values: ["large", "xlarge", "2xlarge"] }
    gha-runner-scale-set:
      githubConfigUrl: https://github.com/example-org/example-repo
      runnerScaleSetName: example-runner-pool
      minRunners: 0
      maxRunners: 2
      template:
        spec:
          serviceAccountName: example-runner-sa
          nodeSelector:
            runner-pool: example-runner-pool
          tolerations:
            - { key: arc-runner, operator: Equal, value: "true", effect: NoSchedule }
```

### Via Terraform `helm_release`

```hcl
resource "helm_release" "runner_pool" {
  name       = "example-runner-pool"
  chart      = "pleme-arc-runner-pool"
  repository = "oci://ghcr.io/pleme-io/charts"
  version    = "~> 0.1"
  namespace  = "example-runner-pool"
  create_namespace = true

  values = [yamlencode({
    serviceAccount = { ... }
    rbac           = { roles = {...} }
    karpenter      = { nodePools = {...} }
    "gha-runner-scale-set" = { ... }
  })]
}
```

A complete generic values reference is in [`examples/example-arc-runner-pool.yaml`](../../examples/example-arc-runner-pool.yaml).

## Prerequisites

- ARC controller installed in the cluster (use `pleme-arc-controller`)
- Karpenter installed in the cluster (any conventional install)
- An EC2NodeClass (or `karpenter.ec2NodeClasses` populated for self-contained pool)
- IAM role provisioned out of band with IRSA trust policy naming the pool's namespace + SA (use Terraform / Pulumi / etc.)

## Multi-pool, multi-tenant

Deploy one HelmRelease per pool. Pools across clusters are independent — each cluster runs its own ARC controller; pool labels (`runs-on:` targets) are cluster-scoped via the runner registration mechanism.

## Bare-metal clusters (no Karpenter)

The chart's Karpenter rendering is values-driven — an empty `karpenter.nodePools` map renders nothing. On bare-metal clusters (pleme-io's `rio` homelab is the reference), the pattern degrades cleanly to:

1. Operator labels + taints designated runner nodes once: `kubectl label node N runner-pool=<pool>` + `kubectl taint node N arc-runner=true:NoSchedule`
2. Chart values set `karpenter.nodePools: {}` (or omit the key entirely)
3. Chart values set `gha-runner-scale-set.template.spec.nodeSelector` + `tolerations` matching the labels/taints above
4. Pod-layer scale-to-zero still applies — AutoscalingRunnerSet's `minRunners=0` means no runner pods exist when no jobs are assigned. Nodes stay up (bare-metal can't JIT-deprovision) but pods come and go.

Full example: [`examples/example-arc-runner-pool-bare-metal.yaml`](../../examples/example-arc-runner-pool-bare-metal.yaml).

A bare-metal Karpenter equivalent (Tinkerbell, Metal3, Cluster API Provider Metal3) could plug in later as a separate values-driven layer, but isn't required for ARC pool basic operation.

## Cost

**Idle cost: $0.** Runner pods only exist when GitHub assigns a job to the pool. Karpenter provisions a node only when a runner pod goes pending. After the workflow completes, the runner pod terminates and Karpenter consolidates the node. The only persistent overhead is the listener pod (~100m CPU / 100Mi memory), which schedules onto existing cluster capacity — no dedicated node for it.

## See also

- `pleme-arc-controller` — the controller pool depends on; deploy once per cluster
- pleme-lib helpers used: `serviceaccount`, `namespacedRBAC`, `karpenterNodePool`, `karpenterEC2NodeClass`
- Upstream chart: [actions/actions-runner-controller](https://github.com/actions/actions-runner-controller/tree/main/charts/gha-runner-scale-set)
