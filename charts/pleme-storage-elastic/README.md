# pleme-storage-elastic

Watcher CronJob that keeps every selected PVC at ~80% utilization.
Implements the storage-tier breathability invariant from
[theory/BREATHABILITY.md §V](../../../theory/BREATHABILITY.md):
"storage cannot scale to zero (data persists), so the breathability
pattern is elastic expansion at 80% utilization."

## How it works

```
every 5 min (configurable):
  watcher pod runs:
    list PVCs matching selector / namespaces / explicit list
    for each PVC:
      capacity = pvc.spec.resources.requests.storage
      used     = kubelet metric (kubelet_volume_stats_used_bytes)
      ratio    = used / capacity
      if ratio > triggerAt (default 0.80):
        if capacity * expandFactor (default 1.25) <= maxSize:
          patch pvc.spec.resources.requests.storage = ceil(capacity * 1.25)
          emit Event PVCExpanded
          increment metric pleme_storage_elastic_expansions_total
        else:
          increment pleme_storage_elastic_at_ceiling_total
          (alert StorageExpansionCeilingReached fires after first sample)
```

Post-expansion target utilization: **64%** (1/1.25 of the new size).
Cooldown between expansions of the same PVC: **600s** (prevents
storms during write bursts).

## When NOT to use

- **Object stores (S3, R2)** — already infinitely elastic. Track
  spend, not space.
- **Local-path / hostPath PVCs without `allowVolumeExpansion: true`**
  in their StorageClass. Expansion will fail; the watcher logs and
  emits Events but the PVC stays at original size.
- **Block-based storage already managed by a CSI driver that does its
  own resize** (e.g. EBS gp3 with auto-resize). Conflict.

## Local ZFS pools

ZFS doesn't auto-expand by adding disks via Kubernetes. For rio-class
single-node clusters with ZFS-backed local-path PVCs, this watcher
**still works on the PVC level** (the local-path provisioner expands
the PVC's allocation in the underlying pool). When the pool itself
nears capacity, a separate alert (`RioStoragePoolUtilization`) fires
to ntfy and the operator physically adds a disk.

## Defaults

- `enabled: false` — chart renders nothing until the operator opts in.
- `triggerAt: 0.80`, `expandFactor: 1.25`, `maxSize: 1Ti`.
- `dryRun: false` — flip true on first rollout to log without patching.
- `schedule: "*/5 * * * *"` — every 5 min.

## Wiring on rio

```yaml
# clusters/rio/infrastructure/storage-elastic/release.yaml
spec:
  values:
    enabled: true
    targets:
      namespaces:
        - monitoring                # vmsingle + victoria-logs PVCs
        - authentik                 # postgres + redis PVCs
        - lareira                   # every lareira-* service
      selector:
        matchLabels:
          breathable: "true"        # opt-in label on PVCs
    policy:
      triggerAt: 0.80
      expandFactor: 1.25
      maxSize: 100Gi                # sane ceiling for a homelab disk
```

## Watcher image

The default `ghcr.io/pleme-io/pleme-storage-elastic` image is a
Nix-built distroless image containing `kubectl` + `jq` + a bash
watcher script. Source: TODO — when the image lands, this README
links the build flake.

## See also

- [theory/BREATHABILITY.md §V — elastic storage at 80%](../../../theory/BREATHABILITY.md)
- [theory/BREATHABILITY.md §VII.7 — helm-first authoring](../../../theory/BREATHABILITY.md)
