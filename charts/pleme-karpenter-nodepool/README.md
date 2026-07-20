# pleme-karpenter-nodepool

Thin, workload-agnostic wrapper exposing pleme-lib's `_karpenter.tpl` helpers (`pleme-lib.karpenterNodePool`, `pleme-lib.karpenterEC2NodeClass`) as a standalone, independently-versioned Helm release.

## Why this chart exists

`pleme-lib` is a Helm **library** chart (`type: library`) — it cannot be installed on its own; it can only be depended on by an application chart. Before this chart, the only consumer of `_karpenter.tpl` was `pleme-arc-runner-pool`, which bundles the Karpenter NodePool/EC2NodeClass declaration together with GitHub Actions Runner Controller-specific resources (IRSA ServiceAccount, RBAC, AutoscalingRunnerSet). Any workload that needs a dedicated Karpenter-backed pool but is NOT a GitHub Actions runner pool had no chart to depend on.

This chart is that generic form: two lines of template (`{{- include "pleme-lib.karpenterEC2NodeClass" . }}` / `{{- include "pleme-lib.karpenterNodePool" . }}`), a `karpenter:` values key, nothing else.

## Usage

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: example-controllers-pool
  namespace: flux-system
spec:
  chart:
    spec:
      chart: pleme-karpenter-nodepool
      version: "0.1.0"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
  values:
    karpenter:
      nodePools:
        controllers: { ... }
      ec2NodeClasses:
        controllers: { ... }
```

See `values.yaml`'s own commented example for the full shape, and `pleme-lib`'s `templates/_karpenter.tpl` header for the authoritative field reference.
