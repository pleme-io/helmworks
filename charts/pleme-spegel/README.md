# pleme-spegel — the co-located SERVE tier for super-cache-ci

**Spegel, adopted (not forked), as a version-controlled pleme-lib Helm
artifact.** Cached image layers serve node-local at P2P/LAN speed instead of
re-pulling from the upstream registry — the serve half of DLC-01 D3.

## What it is

This is the **image-layer serve** complement to the super-cache-ci **store**
keystone:

| Tier | Chart | Caches | Serves |
|------|-------|--------|--------|
| store | `super-cache-ci` | build artifacts (derivations) in Redis L1 / Postgres L2 | the sui daemon fronting `TieredBackend` |
| **serve** | **`pleme-spegel`** | image **layers** already in each node's containerd content store | node-to-node over a P2P mesh |

A layer pulled once onto any node is advertised into the Spegel mesh and served
locally to every other node — so super-cache-ci's warmed layers stop re-hitting
`ghcr.io` / ECR / DockerHub.

## Adopted, not forked

Every byte of P2P/swarm logic is the **upstream `ghcr.io/spegel-org/spegel`
binary** (pinned by digest). This chart is **config-only** — it owns zero swarm
code. The templates are standard Kubernetes (DaemonSet + headless bootstrap
Service + registry NodePort Service + metrics Service + NetworkPolicy + breathe
bands); the only behaviour is Spegel's own `registry` command run with flags.
No Rust, no bespoke skopeo pusher, no from-scratch enxame swarm.

Pinned against upstream **Spegel v0.7.3** (`Chart.appVersion`). Peer discovery
is DNS-bootstrap against the headless `-bootstrap` Service — which needs **no
Kubernetes API access**, so the chart grants **no ClusterRole** (least-privilege
by construction).

## Shadow-first

Adopting the DaemonSet **forms + warms the P2P mesh** (advertise + serve peer
layers) but does **not reroute any node's image pulls**. The containerd
`/etc/containerd/certs.d` mirror hosts — the one node mutation — are written by
an initContainer that is present **only when `registryMirror.enabled: true`**
(default `false`).

- **Advertise / serve = the shadow.** The mesh forms and serves in observe-mode.
- **Flipping the containerd mirror on = the live promotion.** The exact analogue
  of a breathe band's `dryRun:false`. Promote a node pool once the mesh is proven
  warm.

The breathe `MemoryBand` / `CpuBand` on the DaemonSet are likewise emitted
`dryRun:true`.

## NetworkPolicy-scoped

Default-deny both directions, then open exactly:

- **router** (5001 tcp+udp) — the P2P libp2p mesh, peer-to-peer both directions
- **registry** (5000) — the served mirror port (peers + same-node kubelet)
- **DNS** (53 tcp+udp) — egress to the resolver for dns-bootstrap
- **metrics** (9090) — ingress, only when `serviceMonitor.enabled`

No wildcard egress — Spegel never dials the internet; it serves layers already
in the node's containerd store and reaches peers over the in-cluster mesh.

## Promote to live (per node pool)

```yaml
# once the mesh is proven warm — this writes containerd mirror hosts on the node
registryMirror:
  enabled: true
# scope the reroute to exactly the registries super-cache-ci pushes to:
spegel:
  mirroredRegistries:
    - https://ghcr.io
```

## Key values

| Key | Default | Purpose |
|-----|---------|---------|
| `image.repository` | `ghcr.io/spegel-org/spegel` | the ADOPTED upstream |
| `image.digest` | `""` | hard-pin (destination); tag-pinned when empty |
| `registryMirror.enabled` | `false` | **shadow-first gate** — the live reroute flip |
| `spegel.mirroredRegistries` | `[]` (all) | scope the mirror to our registries |
| `ports.{registry,router,metrics}` | `5000/5001/9090` | the upstream plane |
| `breathe.{memory,cpu}.dryRun` | `true` | shadow-first homeostasis |
| `networkPolicy.enabled` | `true` | default-deny + scoped apertures |

## Verify

```sh
helm lint charts/pleme-spegel
helm template pleme-spegel charts/pleme-spegel -n super-cache-ci
helm unittest charts/pleme-spegel
```
