# lareira-camelot-builders

The **camelot nix builder fleet** — a per-arch (`arm64` + `amd64`),
camelot-tainted, 100%-spot, scale-to-zero native-metal builder substrate that
unblocks cold cross-arch Nix builds inside the camelot (`mte-staging`)
environment. Owns **minimal new algebra** — a composition index over
`pangea-spot` (the `nix_builder` catalog), `CamelotNodeGroup`,
`BreatheCloudPool`, `retirada`, and `pleme-lib`.

Design: `scratchpad/camelot-builder-fleet-design.md` (§2i + §2c + §2f).

> Every mutation is a **magma Plan / GitOps commit**, never a direct cloud-API
> call. Every band ships **shadow-first** (`dryRun` + `writeEnabled` both default
> safe-OFF). The operator's two verbs are **declare** (edit values, commit) +
> **observe** (`status.lastCycle` + the enjulho dashboard).

## Two tiers, one substrate

| | Tier A (this chart, shipped) | Tier B (`tierB/`, gated `enabled: false`) |
|---|---|---|
| substrate | standalone SSM `MixedInstancesAsg` (not EKS-joined) | EKS managed node group |
| reached by | cid `ssh-ng` over cordel SSM ProxyCommand | camelot GHA crunkrun Streams |
| store/cache | Attic-in-camelot → cache.nixos.org (on-disk) | sui tiered Redis→Pg→object (never-touch-disk) |
| RAMDISK | static ½-RAM tmpfs `/tmp` (baked in the NixOS AMI) | breathe `MemoryBand` over `emptyDir{Memory}` |
| gate | reuse-only; unblocks the cold-build measurement **today** | `TieredBackend` + sui REAPI worker keystones |

Tier B is **inert** until its keystone gates clear — every `tierB/*` template
gates on `tierB.enabled`. Flipping it on without those gates ships a
non-functional stack; this is the **LiveTODO honesty gate**, never rounded up.

## Tier A templates

| Template | Kind | Notes |
|---|---|---|
| `infratemplate-builder-{arm64,amd64}` | `InfrastructureTemplate` | inline Ruby → `CamelotBuilderNodeGroup.build` (magma applies the AWS ASG) |
| `breathecloudpool-{arm64,amd64}` | `BreatheCloudPool` | node-COUNT band, **shadow-first** (`dryRun` + `writeEnabled` OFF, floor 0, predictive) |
| `interruption-handler-{arm64,amd64}` | `InfrastructureTemplate` | scoped `Spot::InterruptionHandler` → retirada seam (**opt-in**, off by default) |
| `attic-in-camelot` | Deployment + Service (+ PVC) | L4 in-cluster substituter (VPN-independent) |
| `build-queue-exporter` | Deployment + Service + ServiceMonitor | the band's `build_queue_depth` demand signal |
| `enjulho-dashboard` | `PangeaDashboard` | `SuperCacheCiOverview` mixin (observe) |

## The perfClass knob (§2h / §3)

The single load-bearing performance knob — trades cost for wake-certainty,
config-selectable per stream, composing shipped mechanisms
(`on_demand_base_capacity`, the Bid interruption tolerance, the allocation
strategy). It invents no new mechanism.

| `perfClass` | Behaviour |
|---|---|
| `cost-floor` (default) | `beefy_spot`, OD base 0, Batch tolerance — cheapest; a reclaim retries |
| `guaranteed-wake` | `balanced`, OD base 1 (+20% OD) — **wakes even if every spot pool is dry** |
| `dedicated` | OD-only, Critical tolerance — no-spot, SLA-bound |

Set `perfClass: guaranteed-wake` for the measurement / release streams.

## Minimum values

```yaml
arches: [arm64, amd64]
perfClass: cost-floor       # per-stream override → guaranteed-wake for release builds
tierB:
  enabled: false            # LiveTODO — flip when TieredBackend + sui REAPI worker land
```

## Operator path to green (the unblock)

1. Commit the chart with `perfClass: guaranteed-wake` → FluxCD + pangea-operator
   provision the ASGs (magma).
2. Confirm SSM-reachable: `nix store info --store ssh-ng://builder@camelot-builder-arm64-ssm`.
3. Flip `wantAarch64LinuxBuilder = true` in the nix repo + rebuild cid.
4. Run the harness.

The `BreatheCloudPool` starts `dryRun: true / writeEnabled: false` (shadow); the
ASG `desired` stays operator-owned until the band's shadow is proven, then flip
`writeEnabled` to hand breathe the wheel — so the measurement is unblocked
**before** the band goes live.
