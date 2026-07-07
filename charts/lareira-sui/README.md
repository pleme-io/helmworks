# lareira-sui — camelot super-cache-ci sui daemon

The RAM-native, content-addressed Nix build-cache **service** for camelot
(step 2 of the optimized build stack). Packages the PROVEN ground-truth posture
(`sui/contrib/ground-truth`, ran 2026-07-06) as ONE camelot enjulho artifact.

## What it deploys

| Resource | What |
|---|---|
| `Deployment/sui` | the `sui cache serve --backend-config` daemon (canonical `pleme-sui` subchart, tiered cache-serve mode), pinned `role:camelot-builder` + toleration, RAMDISK sandbox at `/build` |
| `Secret/sui-tiered-backend` | the `BackendConfig::Tiered` TOML (Redis L1 → Postgres L2 → S3/local L3, write-through) — DSN in a Secret, never a ConfigMap |
| `Deployment/sui-redis` + `Service` | L1 hot cache (`redis:7-alpine`, allkeys-lru, ephemeral — re-warms from L2) |
| `StatefulSet/sui-postgres` + `Service` + `Secret` | L2 durable content-addressed store (`postgres:17-alpine`, PVC-backed) |
| `MemoryBand/sui-super-cache-ramdisk` | breathe RAMDISK carve (couple pod-limit + emptyDir{Memory}), **shadow-first** |
| `Service/sui` | the Nix binary-cache HTTP endpoint (`/nix-cache-info`, port 80 → 5000) |

## The never-touch-disk invariant

The eval+build sandbox lives on a tmpfs RAMDISK (`emptyDir{medium:Memory}` at
`/build`). `SUI_BUILD_DIR` is the documented contract; **`TMPDIR=/build` is
load-bearing** — `LocalBuilder.build_dir_base` defaults to `std::env::temp_dir()`
(which reads `TMPDIR`), so pointing `TMPDIR` at the RAMDISK is what actually keeps
eval+build off durable disk. The durable store is Postgres (L2), never disk.

## Two gates before it serves (tier-honest)

1. **Image** — the tiered serve capability needs an image built `--features tiered`
   (Redis + Postgres arms) **and** carrying the ground-truth `cache serve
   --backend-config` wiring. The published `amd64-latest` has NEITHER (main builds
   no features + no `--backend-config`). Set `pleme-sui.image.tag` to the tiered
   autobump tag. See the runbook.
2. **Secret** — set `postgres.auth.existingSecret` to a cofre/SOPS-rendered
   credential; do not ship the chart-default password.

## Declare + observe

Edit `values.yaml` (or the HelmRelease values), commit — FluxCD converges it.
Observe via `kubectl get`, the enjulho SuperCacheCiOverview dashboard, and the
breathe MCP. Never `helm install` by hand. Example HR:
`examples/helmrelease-camelot.yaml`.

Runbook: `nix/.../scratchpad/step2-sui-daemon-runbook.md`.
