# helmworks

Reusable Helm chart library for pleme-io services.

## Overview

Helmworks contains all Helm charts used by the pleme-io platform. Charts are built on a shared library chart (`pleme-lib`) that provides common templates for deployments, services, ingress, and RBAC. The flake exposes lifecycle apps (lint, template, package, push) via substrate's `mkHelmAllApps` and builds chart tarballs as Nix packages for CI caching.

## Charts

| Chart | Description |
|-------|-------------|
| `pleme-lib` | Shared Helm template library |
| `pleme-microservice` | Standard microservice |
| `pleme-worker` | Background worker |
| `pleme-web` | Web frontend |
| `pleme-cronjob` | Scheduled jobs |
| `pleme-migration` | Database migrations |
| `pleme-operator` | Kubernetes operators |
| `pleme-namespace` | Namespace provisioning |
| `pleme-statefulset` | Stateful workloads |
| `pleme-database` | Database instances |
| `pleme-cache` | Cache (Redis) instances |
| `pleme-bootstrap` | Cluster bootstrap |
| `pleme-gpu-workload` | GPU workloads |
| `hanabi` | BFF server |
| `shinka` | Migration operator |
| `kenshi` | Testing operator |
| `arachne` | Scraping framework |
| `sekiban` | Integrity gating controller |
| `headscale` | Headscale VPN |

## Usage

```bash
# Build a chart tarball
nix build .#pleme-microservice

# Push charts to OCI registry
nix run .#push-pleme-microservice

# Dev shell with helm, kubectl, yq
nix develop
```

Registry: `oci://ghcr.io/pleme-io/charts`

## License

MIT
