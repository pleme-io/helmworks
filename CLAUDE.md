# Helmworks

Reusable Helm chart library for pleme-io internal services.

## Structure

```
charts/
  pleme-lib/              # Library chart (type: library) — shared named templates
  pleme-microservice/     # HTTP service (REST/GraphQL/gRPC)
  pleme-worker/           # Background worker (no Service)
  pleme-web/              # Frontend + BFF (HTTP + WebSocket)
  pleme-cronjob/          # Scheduled jobs
  pleme-migration/        # Shinka DatabaseMigration CRD
  pleme-operator/         # K8s operator with RBAC

tests/                    # helm-unittest suites
examples/                 # Example values files per service
nix/                      # Nix build helpers (consumed by flake.nix)
```

## Nix Apps

All chart lifecycle operations are `nix run` commands:

| Command | Description |
|---------|-------------|
| `nix run .#lint` | Lint all charts |
| `nix run .#lint:pleme-microservice` | Lint a specific chart |
| `nix run .#package` | Package all charts to `dist/` |
| `nix run .#package:pleme-microservice` | Package a specific chart |
| `nix run .#push` | Push all charts to OCI registry |
| `nix run .#push:pleme-microservice` | Push a specific chart |
| `nix run .#release` | Full lifecycle: lint + package + push |
| `nix run .#release:pleme-microservice` | Release a specific chart |
| `nix run .#template -- pleme-microservice examples/releases.yaml` | Render templates |

## Chart Architecture

**pleme-lib** is a library chart providing named templates:
- `pleme-lib.deployment` — standard Deployment
- `pleme-lib.service` — ClusterIP Service
- `pleme-lib.serviceaccount` — ServiceAccount
- `pleme-lib.servicemonitor` — Prometheus ServiceMonitor
- `pleme-lib.networkpolicy` — deny-all + allow-dns + allow-prometheus
- `pleme-lib.pdb` — PodDisruptionBudget
- `pleme-lib.hpa` — HorizontalPodAutoscaler

Application charts invoke these via `{{- include "pleme-lib.deployment" . }}`.

## Security Baseline (enforced)

All charts enforce:
- `runAsNonRoot: true`, `runAsUser: 1000`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`

## Integration with k8s repo

Charts are pushed to `oci://ghcr.io/pleme-io/charts`. FluxCD HelmReleases reference them:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
spec:
  chart:
    spec:
      chart: pleme-microservice
      version: "0.1.0"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
```

Environment-specific overrides use kustomize patches on the HelmRelease.
Secrets stay as SOPS-encrypted Secret YAMLs — never in Helm values.

## Adding a New Chart

1. Create `charts/<name>/` with `Chart.yaml` depending on `pleme-lib`
2. Add template files invoking `pleme-lib.*` named templates
3. Create `values.yaml` with sensible defaults
4. Add tests in `tests/<name>/`
5. Add example values in `examples/`
6. Add to `chartDefs` list in `flake.nix`
