# pangea-operator chart

Helm chart deploying the [pangea-operator](https://github.com/pleme-io/pangea-operator)
controller plus a breathable, KEDA-scaled worker pool for fleet-wide
Pangea/OpenTofu reconciliation.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│ controller (1 pod, leader-elected)                   │  ← pleme-operator lib
│   watches CRs, dispatches PangeaWorkUnits            │
│   exposes pangea_workunit_pending_total{work_class}  │
└──────────┬───────────────────────────────────────────┘
           │ creates
           ▼
┌──────────────────────────────────────────────────────┐
│ PangeaWorkUnit CRs (one per pending action)          │
└──────────┬───────────────────────────────────────────┘
           │ KEDA Prometheus trigger
           ▼
┌──────────────────────────────────────────────────────┐
│ pangea-worker pools (per class, 0..N pods)           │  ← pleme-worker lib
│   small  (1Gi)  | medium (2Gi)  | large (8Gi)        │
│   each: own Deployment + ScaledObject                │
│   each: claims a WorkUnit + runs pangea synth +      │
│         tofu plan/apply                              │
└──────────────────────────────────────────────────────┘
```

## Installing

```sh
# Default: chart renders nothing until you flip enabled: true.
helm install pangea ./charts/pangea-operator \
  --namespace pangea-system \
  --create-namespace \
  --set enabled=true
```

KEDA must be installed in the cluster (the Pleme-IO standard infra).

## Breathability

| State | Resident |
|---|---|
| Idle (no workspaces pending) | 1 controller pod (~256 MiB) |
| Single workspace push | +1 worker (cold ~30s, drains in <5m, then back to 0) |
| Burst (50 medium workunits) | scales medium pool to maxReplicas=10, drains in ~5 batches |
| Backed up (>20 pending, no claims for 5m) | `PangeaWorkUnitsBacklog` warning fires |

The `cooldownPeriod` is 300s by default — workers stay around for 5
minutes after the last claim, then scale to zero. Tune via
`workers.scaling.cooldownPeriod`.

## Worker classes

| Class | Resources | maxReplicas | Use |
|---|---|---|---|
| `small`  | 100m / 256Mi → 1 / 1Gi | 5 | DNS records, IAM roles, simple S3 buckets |
| `medium` | 500m / 1Gi → 2 / 2Gi   | 10 | VPC, EKS, multi-resource architectures |
| `large`  | 2 / 4Gi → 4 / 8Gi      | 3 (opt-in) | Big tofu graphs, multi-region, deep cross-stack refs |

Authors set `spec.workClass` on the parent CR (defaults to
`controller.config.workClassDefault`, which is `medium`).

## Provider plugin cache (optional)

The default value `workers.providerPluginCache.enabled: false` means
each worker pod re-downloads tofu provider plugins from scratch
(adds ~10s per cold start).

To share a cache across workers, set:

```yaml
workers:
  providerPluginCache:
    enabled: true
    storageClassName: csi-rwx-or-equivalent
    size: 5Gi
    accessMode: ReadWriteMany
```

Workers will mount the PVC at `/home/pangea/.terraform/plugin-cache`
read-write. The controller writes-through, workers read.

## Default-OFF

Like every pleme-helm-style chart, `enabled: false` is the default.
Helm renders nothing until you opt in. The cluster's pangea footprint
is zero until the operator approves the change.

## Pillar 11 alignment

The chart ships `observability.prometheusRule.enabled: true` by default
with the `PangeaWorkUnitsBacklog` rule pre-wired. Combined with the
`severity: warning` label, this routes through the standard pleme-io
alerting tree (rio-warning ntfy topic on the homelab variant; the
matching Datadog monitor on the SaaS variant).

## See also

- [pangea-operator design doc](https://github.com/pleme-io/pangea-operator/blob/main/docs/design/0003-helmworks-chart-and-breathable-workers.md)
- [pleme-operator lib chart](../pleme-operator/) — controller composition
- [pleme-worker lib chart](../pleme-worker/) — worker composition
- [KEDA prometheus trigger](https://keda.sh/docs/scalers/prometheus/)
