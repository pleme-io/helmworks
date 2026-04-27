# Use-case primitives — `/usecases/`

> Companion: [`COMPLIANCE-OVERLAYS-DESIGN.md`](./COMPLIANCE-OVERLAYS-DESIGN.md),
> [`COMPLIANCE-PROOF.md`](./COMPLIANCE-PROOF.md).

A **use-case primitive** is a typed values fragment in `/usecases/` that
composes the right overlay set + workload-shape defaults for a
recurring compliance posture. The user-facing pattern is one line:

```bash
helm install my-service oci://ghcr.io/pleme-io/charts/pleme-microservice \
  -f usecases/dod-il5-microservice.yaml \
  -f my-service-overrides.yaml
```

`my-service-overrides.yaml` is small (image, ports, ingress hosts).
The use-case file does the heavy compliance lifting.

## Why this is provable

A use-case primitive has two parts:

1. **Overlay declaration**: `compliance.overlays: [...]` — composing
   proven overlays from the registry.
2. **Workload-shape defaults**: replicas, resources, persistence,
   ingress shape sensible for the use-case.

The compliance proof for a use-case is **the union of the proofs of its
declared overlays**. There is no per-use-case proof work because the
overlays are individually proven and compose by union.

## Library layout

```
usecases/
  README.md                              # consumer-facing index
  fedramp-high-microservice.yaml         # civilian regulated SaaS
  dod-il5-microservice.yaml              # DoD CUI national-security
  hipaa-microservice.yaml                # ePHI-handling SaaS
  cmmc-l3-microservice.yaml              # DoD contractor CUI
  regulated-microservice.yaml            # fedramp-moderate (lightest)
```

Each file pairs with a smoke test in
`tests/usecases/usecases_test.yaml` that asserts:
- The use-case applies cleanly to a workload chart
- `data.overlays` in the rendered compliance manifest contains the
  expected overlay names (after closure resolution)
- `data.controls` contains the expected NIST/HIPAA/CMMC/DoD control IDs

## Adding a use-case

1. **Pick the regimes** that apply (FedRAMP level + DoD/HIPAA/CMMC/PCI/NIS2/...).
2. **Look up the overlays** in `pleme-lib.overlay.registry` (declared
   in `_overlay_dispatch.tpl`).
3. **Create `usecases/<name>.yaml`**:
   ```yaml
   compliance:
     overlays: [overlay-1, overlay-2, ...]
     enforce: true
     # required overlay configuration (audit retention, OIDC, mTLS, …)
   # workload defaults sensible for the use-case
   replicaCount: 3
   resources:
     requests: { cpu: 100m, memory: 128Mi }
     limits: { memory: 512Mi }
   image:
     pullPolicy: Always
   monitoring:
     enabled: true
   ingress:
     enabled: true
     className: nginx
   attestation:
     enabled: true
   ```
4. **Add a row** to `usecases/README.md`'s library table.
5. **Add a smoke test** in `tests/usecases/usecases_test.yaml`:
   ```yaml
   - it: "[usecase] <name> — <regimes>"
     values:
       - ../../usecases/<name>.yaml
     set:
       image.repository: ghcr.io/pleme-io/example
       image.tag: "sha256:..."
       # other minimum overrides
     asserts:
       - matchRegex:
           path: data.overlays
           pattern: "<expected overlay>"
       - matchRegex:
           path: data.controls
           pattern: "<expected control ID>"
   ```
6. Commit. The next consumer chart that wants this use-case is one
   `helm install -f` line away.

## Conventions

- **One overlay = one use-case**: `fedramp-high-microservice` declares
  only `[fedramp-high]`; the cascade pulls in `fedramp-moderate`. Don't
  pre-declare cascaded overlays — let the registry handle closure.
- **Overlay configuration goes in the use-case file**: things like
  `compliance.audit.retentionDays`, `compliance.fips.runtime`,
  `compliance.airgap.role` — values an overlay needs to be valid.
- **Workload-specific values go in operator overrides**: image repo,
  service ports, ingress hosts, replica count if it differs from the
  use-case's default.
- **Use-case files are NOT installed directly**: they're values
  fragments. The consumer chart is one of `pleme-microservice` /
  `pleme-statefulset` / `pleme-cronjob` / `pleme-worker`.

## Composition with multiple use-cases

Helm's multi-`-f` deep-merges, so an operator can stack:

```bash
helm install -f usecases/dod-il5-microservice.yaml \
             -f usecases/regional-eu.yaml \      # hypothetical: forces EU residency
             -f my-overrides.yaml
```

The right side wins on conflicts. This means use-cases are **layered**:
a base regime (DoD-IL5) + a regional/customer overlay (EU residency,
specific tenancy) + workload-specific values. Each layer is a small
typed file.

## Future use-cases (one file each)

- `fedramp-high-statefulset.yaml` — for databases / persistence layers
- `dod-il5-database.yaml` — StatefulSet variant of dod-il5
- `regulated-cronjob.yaml` — batch workload regime
- `pci-dss-payment-gateway.yaml` — adds PCI-DSS overlay (when available)
- `nis2-eu-sovereign.yaml` — adds NIS2 + EU residency overlays
- `cmmc-l2-microservice.yaml` — CMMC L2 (lighter than L3)
- `iso27001-microservice.yaml` — ISO 27001 Annex A controls

Each is one YAML file. The mechanical proof inherits from the overlay
registry.
