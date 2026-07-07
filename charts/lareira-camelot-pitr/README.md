# lareira-camelot-pitr

The **enjulho wrapper** that lets **camelot** restore its own secrets to a point in
time — a **separate, parallel consumer** of the generic pleme-io PITR engine.

## What this is (and is not)

- **IS** a NEW consumer surface that pins the SAME
  `ghcr.io/pleme-io/{pitr-tools,function-pitr-drill}@sha256:…` digests
  (TOOL-DISTRIBUTION — consume, never fork/edit) and fills the SAME typed
  `RestoreInput` surface with **camelot** values.
- **IS NOT** an edit of the engine, and **IS NOT** the team's in-review
  `pitr-akeyless` chart in `akeyless-environments`. The team reviews THEIR consumer;
  camelot runs OURS; the two never touch (different repo · branch · Flux scope · ns ·
  creds · data-plane · config). Both are external OSS consumers of the same engine.

## The honest divergence — camelot has no RDS

camelot's data plane is **in-cluster gp3-PVC MySQL** (a StatefulSet), not AWS RDS. The
engine's shipped RDS path (`restoreToPointInTime`) is inapplicable. So camelot supplies
**empty `sourceDbInstances`** (the engine's `emitRDS` iterates an empty map → nil, no
RDS emitted — verified read-only against `function/rds.go` + `function/kind_pitr.go`)
and its restore VECTOR is a **CSI VolumeSnapshot** of the gp3 PVC → a restore PVC → an
ephemeral `camelot-mysql-restore` StatefulSet, fed to the UNCHANGED engine as
`extraResources`. The generic `pitr-tools` canary/verify Jobs prove the round-trip.

**Recovery granularity is snapshot-point** (the snapshot cadence), **NOT
arbitrary-second PITR** — binlog replay forward (`restore.binlogReplay`) is DESIGN/M3.
A canary round-trip is a recovery **mitigation**, not a no-row-lost theorem.

## Breathability

The restore workload is breathe-managed on camelot's tainted 100%-spot nodes:
`MemoryBand`/`CpuBand`/`StorageBand` (all `dryRun: true`, shadow-first — the camelot
footgun guard) right-size the transient restore StatefulSet + PVC while they exist. The
drill's own create→verify→teardown lifecycle **is** the scale-to-zero. The restored DB
classifies as a breathe `DatabaseBand` transient `SingleWriter` (`failoverPolicy: None`
— vacuous for a lone transient writer); the `DatabaseBand` CRD is LANDING, so `emitCR`
defaults **off**. Because the restore DB is a POD (not RDS), Mem/Cpu bands genuinely
reach it — a cleaner breathe fit than the RDS-backed case.

## Declare-and-observe (zero-shell)

The operator's only two verbs are **declare** and **observe** — never
plan/apply/destroy:

1. **Declare** — edit `pitrsession.restoreTime` / `secretNames` (or commit the
   `CamelotPITRSession` CR under `clusters/camelot/pitr/`). Commit → Flux converges.
2. **Observe** — read `status.retrievedSecrets` / `status.phase` /
   `status.cleanupStatus` via kubectl/MCP (JSON receipt).

Committing the CR is the whole zero-shell trigger — no bash tool authored. (An
ergonomic `nix run .#camelot-pitr declare|observe` keyway wrapper is the DESIGN layer.)

## Tier-honest status

- **Shipped / provable now:** the chart renders + `helm lint` + `helm unittest` (12/12)
  green — the layer is **WIRED** (engine by digest, RestoreInput filled, restore vector,
  breathe bands, isolation, RBAC, cofre SecretRef, camelot-scoped XRD/CR).
- **OPERATOR-GATED (named, not claimed working):** the LIVE drill needs (1) **Crossplane
  core + provider-kubernetes** on the camelot floor, (2) a **CSI VolumeSnapshotClass**
  (`restore.snapshotClassName`), and (3) **camelot akeyless creds via cofre**
  (`externalSecrets`). Until those exist, a rendered `CamelotPITRSession` simply stays
  `Pending` — harmless, node-gated, exactly like the camelot C0 skeleton.

## The two digests

| Artifact | Pin |
|---|---|
| `pitr-tools` (drill-step binaries) | `@sha256:8dc18919…3576` |
| `function-pitr-drill` (drill engine) | `@sha256:448384b1…d878` |

Both are read from the engine's GHCR at authoring time; `_helpers.tpl` fails the render
if either is empty or not `@sha256`-pinned (HERMETIC SUPPLY CHAIN).
