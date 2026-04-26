# pleme-storage-elastic watcher image

Source for the container image referenced by the
[pleme-storage-elastic chart](../). Implements the PVC autosize logic
from [theory/BREATHABILITY.md §V](../../../../theory/BREATHABILITY.md):
keep watched PVCs at ~80% utilization, expand by `EXPAND_FACTOR`
(default 1.25) when triggered, never shrink, hard ceiling at `MAX_SIZE`.

## Layout

```
image/
├── flake.nix       Nix-built distroless OCI image (kubectl + python3 + bash + watcher.sh)
├── watcher.sh      The watcher entrypoint
└── README.md       this file
```

## Build

```sh
cd image/
nix build .#image
# Result: ./result is a docker-archive tarball (loadable with podman/docker)
```

## Push to GHCR

```sh
# Authenticate to GHCR first (one-time):
echo "$GHCR_TOKEN" | skopeo login ghcr.io -u <github-user> --password-stdin

cd image/
nix run .#push
# Pushes ghcr.io/pleme-io/pleme-storage-elastic:0.1.0 + :latest
```

## Run locally

```sh
cd image/
nix develop
export NAMESPACES='[]'
export SELECTOR='{"matchLabels":{"breathable":"true"}}'
export DRY_RUN=true
export USAGE_QUERY_URL=http://vmsingle-vm.monitoring.svc:8429
./watcher.sh
```

`DRY_RUN=true` makes the watcher log what it *would* expand without
patching anything. Useful for first rollout to verify the selector +
threshold + max-size triple.

## Environment variables

| Var | Default | Meaning |
|---|---|---|
| `TRIGGER_AT` | `0.80` | Fraction of capacity that triggers expansion |
| `EXPAND_FACTOR` | `1.25` | Multiplier applied to current capacity |
| `MAX_SIZE` | `100Gi` | Hard ceiling per PVC; emits `PVCAtCeiling` if breached |
| `COOLDOWN_SECONDS` | `600` | Min interval between expansions of the same PVC |
| `DRY_RUN` | `false` | If `true`, log only — don't patch |
| `NAMESPACES` | `[]` | JSON array of namespace names; `[]` = all |
| `PVCS` | `[]` | JSON array of explicit `{namespace,name}` pairs (overrides selector) |
| `SELECTOR` | `{}` | JSON label selector (`{"matchLabels":{"k":"v"}}`) |
| `USAGE_QUERY_URL` | `(unset)` | Prometheus-compatible `/api/v1/query` URL for `kubelet_volume_stats_used_bytes` |

## Watcher events (stdout JSON)

```jsonc
// One per scanned PVC that exceeded the trigger and is being expanded.
{"event":"PVCExpanding","namespace":"monitoring","pvc":"vl-volume-victoria-logs-0","from":"50Gi","to":"63Gi","ratio":0.82,"dryRun":false}
{"event":"PVCExpanded", "namespace":"monitoring","pvc":"vl-volume-victoria-logs-0","from":"50Gi","to":"63Gi"}

// Skipped because of cooldown.
{"event":"PVCInCooldown","namespace":"monitoring","pvc":"vl-volume-victoria-logs-0","sinceSeconds":120}

// Skipped because expansion would breach MAX_SIZE.
{"event":"PVCAtCeiling","namespace":"monitoring","pvc":"vl-volume-victoria-logs-0","capacity":"100Gi","max":"100Gi"}

// Couldn't fetch usage metrics (no metrics endpoint or PVC missing).
{"event":"PVCMetricsMissing","namespace":"monitoring","pvc":"vl-volume-victoria-logs-0"}

// Final summary line.
{"event":"WatcherRunComplete","timestampEpoch":1729891234}
```

The chart's PrometheusRule alerts on the `_expansions_total` and
`_at_ceiling_total` counters — those need a metrics exporter sidecar
that consumes these events. Tracked as the next iteration; for now
the events land in VictoriaLogs via Vector and the operator can grep.

## Why bash + python instead of Rust?

Pragmatism. The watcher is a CronJob that runs every 5 min for ~5
seconds. A 40 MiB image with kubectl + python3 starts cold in ~1 sec.
A Rust binary would shave milliseconds off boot but at the cost of
days of implementation. Once the watcher's behavior is settled, a
proper Rust port (consuming pleme-io's shikumi config + tsunagu IPC)
becomes a 2-day refactor.
