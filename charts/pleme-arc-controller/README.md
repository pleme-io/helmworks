# pleme-arc-controller

Cluster-level [GitHub Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) install. Wraps the upstream `gha-runner-scale-set-controller` chart and adds an ExternalSecret that materializes the controller's GitHub App credentials from the cluster's secret store (default: a `ClusterSecretStore` named `cluster-secret-store`; override to point at any External Secrets Operator-compatible backend — Vault, AWS Secrets Manager, etc.).

Deploy **one per cluster**. Multiple `pleme-arc-runner-pool` releases register their AutoscalingRunnerSets against this controller.

## Resources rendered

- **ExternalSecret** `arc-github-app-secret` — pulls a remote secret containing `github_app_id` / `github_app_installation_id` / `github_app_private_key` from the configured ClusterSecretStore
- **All resources from the upstream `gha-runner-scale-set-controller` chart** — Deployment(s), ServiceAccount, RBAC, CRDs (CustomResourceDefinition installations live in the chart's templates)

## Installation

### Via FluxCD HelmRelease (preferred)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: arc-controller
  namespace: flux-system
spec:
  targetNamespace: actions-runner-controller
  install:
    createNamespace: true
    crds: CreateReplace      # CRDs are installed by the upstream chart
  chart:
    spec:
      chart: pleme-arc-controller
      version: "~0.1.0"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
  values:
    externalSecret:
      clusterSecretStoreName: cluster-secret-store
      secrets:
        arc-github-app-secret:
          dataFrom:
            - extract:
                key: /example/secrets/arc-github-app-secret
    gha-runner-scale-set-controller:
      replicaCount: 3
```

### Via Terraform `helm_release`

```hcl
resource "helm_release" "arc_controller" {
  name       = "arc-controller"
  chart      = "pleme-arc-controller"
  repository = "oci://ghcr.io/pleme-io/charts"
  version    = "~> 0.1"
  namespace  = "actions-runner-controller"
  create_namespace = true

  values = [yamlencode({
    externalSecret = {
      secrets = {
        "arc-github-app-secret" = {
          dataFrom = [{ extract = { key = "/example/secrets/arc-github-app-secret" } }]
        }
      }
    }
    "gha-runner-scale-set-controller" = {
      replicaCount = 3
    }
  })]
}
```

A complete generic values reference is in [`examples/example-arc-controller.yaml`](../../examples/example-arc-controller.yaml).

## Prerequisites

- **External Secrets Operator** installed in the cluster
- **A ClusterSecretStore** wired to your secret backend
- **The remote secret seeded** — three keys (`github_app_id`, `github_app_installation_id`, `github_app_private_key`) at the path passed to `externalSecret.secrets.arc-github-app-secret.dataFrom[0].extract.key`

## How GitHub App credentials are seeded

The pattern: a GitHub App is created out of band, credentials extracted, stored in your secret backend at a known path. The `pleme-arc-controller` chart's ExternalSecret pulls them into the cluster as a Kubernetes Secret. The controller Deployment's env vars reference that secret. Rotation is a backend-side operation; the cluster picks up new values on the next ESO refresh interval.

## Multi-cluster

Each cluster gets its own `pleme-arc-controller` install. The remote secret can be the same across clusters (one App, multiple installs) or different (one App per cluster — better blast-radius isolation).

## See also

- `pleme-arc-runner-pool` — runner pool chart that registers with this controller
- pleme-lib helpers used: `externalSecret`
- Upstream chart: [actions/actions-runner-controller](https://github.com/actions/actions-runner-controller/tree/main/charts/gha-runner-scale-set-controller)
