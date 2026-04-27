# Compliance Use-Case Primitives

> "Primitives are generated for that type" — declarative use-case
> primitives compose the right overlay set for a workload pattern. A
> consumer chart imports a use-case as one values file; the workload
> inherits the full compliance posture without thinking.

## How it works

Each YAML file in this directory is a **typed use-case primitive** —
a values fragment declaring:

1. The compliance overlay set (`compliance.overlays: [...]`)
2. Workload-shape defaults sensible for the use-case (replicas,
   resources, persistence, ingress shape)
3. Mandatory configuration the overlays require (auth provider, FIPS
   runtime, mirror schedule, …)

Consumer charts compose the use-case + their workload-specific values
via Helm's standard multi-`-f` deep-merge:

```bash
helm install my-service oci://ghcr.io/pleme-io/charts/pleme-microservice \
  --namespace regulated --create-namespace \
  -f /usecases/dod-il5-microservice.yaml \
  -f my-service-overrides.yaml
```

`my-service-overrides.yaml` is small — typically just image, ports,
ingress hosts. The use-case file does the heavy compliance lifting.

## Compounding

Adding a new use-case is **one file**:
- `usecases/iso27001-saas-platform.yaml`
- `usecases/pci-dss-payment-gateway.yaml`
- `usecases/nis2-eu-sovereign-microservice.yaml`
- `usecases/cmmc-l3-classified-bid-portal.yaml`

Each file is provably correct because it just composes proven overlays
from `pleme-lib`'s overlay registry. No per-use-case proof work needed —
the proof is the union of the applied overlays' proofs.

## Library

| File | Overlays | Workload shape | Description |
|---|---|---|---|
| `fedramp-high-microservice.yaml` | fedramp-high | Deployment, Ingress, mTLS | The basic regulated SaaS workload |
| `dod-il5-microservice.yaml` | dod-il5 (cascades fedramp-high + airgap-consumer + supplychain + fips) | Deployment, Ingress, FIPS+IronBank | DoD CUI national-security workload |
| `dod-il5-database.yaml` | dod-il5 | StatefulSet, encrypted PVC, no Ingress | DoD CUI persistence layer |
| `hipaa-microservice.yaml` | fedramp-moderate + hipaa + supplychain | Deployment, Ingress, mTLS, 6yr audit | ePHI-handling SaaS workload |
| `cmmc-l3-microservice.yaml` | cmmc-l3 (cascades fedramp-high + dod-il4 + supplychain) | Deployment, Ingress | CMMC L3 / NIST 800-171+172 |
| `regulated-microservice.yaml` | fedramp-moderate (lightest) | Deployment, Ingress | Civilian-agency regulated workload |

## Adding a use-case

1. Pick the regimes that apply (FedRAMP level + DoD/HIPAA/CMMC/PCI/NIS2/...)
2. Look up the corresponding `pleme-lib` overlays in
   `pleme-lib.overlay.registry` (declared in `_overlay_dispatch.tpl`)
3. Create `usecases/<your-name>.yaml` with:
   ```yaml
   compliance:
     overlays: [overlay-1, overlay-2, ...]
     # required overlay configuration
   # workload defaults
   ```
4. Add a row to the table above
5. Add a smoke test in `tests/usecases/<your-name>_test.yaml` asserting:
   - The use-case file applies cleanly to `pleme-microservice` /
     `pleme-statefulset` / `pleme-cronjob`
   - The expected overlay set is in the rendered manifest's
     `data.overlays` ConfigMap field
   - The expected control IDs are in `data.controls`
6. Commit. The next consumer chart that wants this use-case is one
   `helm install -f` line away.

The proof: for any `usecases/<name>.yaml` whose declared overlays are in
the registry, applying the use-case to a workload chart produces
manifests that satisfy the union of all declared overlays' controls.
This is the same composition rule that makes the overlay registry
provable; use-cases inherit the proof by construction.
