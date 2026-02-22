# Helmworks

Reusable Helm chart library for pleme-io internal services.

## Structure

```
charts/
  pleme-lib/           # Library chart (type: library) — shared named templates
  pleme-microservice/  # HTTP services (REST/GraphQL/gRPC) with Service + ServiceMonitor
  pleme-worker/        # Background workers (no Service)
  pleme-web/           # Frontend web apps served by Hanabi BFF
  pleme-cronjob/       # Scheduled CronJob workloads
  pleme-migration/     # Database migration Jobs (Shinka pattern)
  pleme-operator/      # Kubernetes operators with ClusterRole RBAC
tests/                 # helm-unittest test suites per chart
examples/              # Example values files for real services
```

## Architecture

- **pleme-lib** provides named templates (deployment, service, probes, security, networkpolicy)
- Application charts depend on pleme-lib and compose its templates
- Charts are packaged and pushed to `oci://ghcr.io/pleme-io/charts/` as OCI artifacts
- FluxCD reconciles HelmRelease CRDs that reference these charts
- Kustomize overlays patch HelmRelease values for environment-specific config

## Key Design Decisions

- **Security baseline enforced**: runAsNonRoot, readOnlyRootFilesystem, drop ALL capabilities
- **Secrets stay outside Helm**: SOPS-encrypted Secret YAMLs, referenced via envFrom/secretKeyRef
- **OCI distribution**: Charts pushed to GHCR, FluxCD pulls via OCI HelmRepository
- **Kustomize overlays preserved**: Image tags, replicas, resources patched via kustomize on HelmRelease

## Commands

```bash
nix run .#lint      # Lint all charts
nix run .#package   # Package all charts to dist/
nix run .#push      # Push packaged charts to OCI registry
nix run .#release   # Full lifecycle: lint, package, push
nix develop         # Dev shell with helm + chart-testing
```

## Adding a New Chart

1. Create `charts/pleme-{type}/` with `Chart.yaml` depending on `pleme-lib`
2. Add templates that invoke `pleme-lib.*` named templates
3. Add example values in `examples/`
4. Add tests in `tests/pleme-{type}/`
5. Run `nix run .#lint` to validate

## Adding a Service to K8s Repo

1. Create `shared/infrastructure/{service}/base/helmrelease.yaml`
2. Reference `pleme-charts` HelmRepository and the appropriate chart
3. Set values inline on the HelmRelease
4. Environment overrides via kustomize patches on the HelmRelease

## Anti-Patterns

- Never embed secrets in Helm values — use secretKeyRef/envFrom
- Never run `helm install` directly — always via FluxCD HelmRelease
- Never duplicate pleme-lib templates in application charts — extend, don't copy
