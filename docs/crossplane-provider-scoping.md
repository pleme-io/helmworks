# Crossplane provider scope-by-default

A large Upbound/Crossplane provider install can destabilize a Kubernetes
control plane **without any workload doing anything wrong** — purely from the
*number and size* of installed CRDs. This doc explains the mechanism, the
feature-neutral fix the pleme-lib substrate provides, and an owner-runnable
experiment to prove the fix on a cluster before committing it.

## The mechanism (why a broad install hurts)

The apiserver maintains an aggregated `/openapi/v2` document covering **every
installed CRD**. The CRD shared-informer's fixed ~300s periodic resync
re-delivers all CRDs to the legacy v2 OpenAPI controller, which **re-merges the
entire document** — an `O(N_CRDs)` cost that repeats every 5 minutes, on every
apiserver, forever. It is stock Kubernetes behaviour, not tunable on managed
control planes (EKS/GKE/AKS).

Upbound AWS provider CRDs are **large** (~700 KB of schema each, mirroring the
full Terraform resource surface). A v2 provider family installs **both** API
generations (`*.aws.upbound.io` legacy **and** `*.aws.m.upbound.io` namespaced)
by default. Installing six service families to use one service can mean **~185
CRDs backing a handful of real resources** and a ~16 MB OpenAPI doc re-merged
twice a minute across the fleet — enough sustained memory pressure to provoke
managed-control-plane recycles.

This is documented upstream (kube #105932 ≈ 3 MiB apiserver memory per CRD;
Crossplane's "Provider Families" + "Disabling Unused Managed Resources" guides).
**The upstream remedy is not a code patch — it is to install fewer CRDs.** So
running these providers at scale *means* scoping them.

## The fix — two feature-neutral levers (no capability lost)

Both are expressed through `.Values.crossplane.*` and rendered by
`_crossplane.tpl`. Nothing is *removed* permanently — a deactivated kind is
re-activated by a one-line edit; an unused family is reinstalled by adding a
map entry.

1. **Provider selection** (`crossplane.providers`) — install only the service
   providers a workload uses. Each family you *don't* list contributes zero
   CRDs. (Existing primitive: `pleme-lib.crossplaneProvider`.)

2. **Managed-resource activation** (`crossplane.managedResourceActivationPolicies`)
   — for the families you *do* install, a `ManagedResourceActivationPolicy`
   keeps only the MRs you use **Active** (their CRD served); everything else
   stays Inactive and contributes zero schema to `/openapi/v2`. This is the
   lever that drops the unused second API generation. (New primitive:
   `pleme-lib.crossplaneManagedResourceActivationPolicy`, alias `crossplaneMRAP`.)

```yaml
crossplane:
  providers:
    provider-aws-rds:                 # ONLY the services in use
      registry: xpkg.upbound.io/upbound
      name: provider-aws-rds
      version: "2.5.3"
  managedResourceActivationPolicies:
    minimal:
      activate:
        - instances.rds.aws.upbound.io   # one exact kind …
        - "*.rds.aws.upbound.io"         # … or a whole service by glob
      # apiVersion: apiextensions.crossplane.io/v2alpha1   # OVERRIDE per cluster
```

**Verify-point before applying:** confirm the cluster serves the MRAP/MRD
surface and at which apiVersion —
`kubectl api-resources | grep -i managedresourceactivationpolicy`. Override
`apiVersion:` on the entry if it differs from the `v2alpha1` default.

## Owner-runnable experiment — prove it before committing

Run on a **non-production** cluster first; the control plane is shared across
all tenants, so the change is cluster-wide. The experiment is read-heavy and
fully reversible.

**Before** (baseline):

```bash
# OpenAPI doc size (the per-merge cost)
kubectl get --raw /openapi/v2 | wc -c
# total served CRDs
kubectl get crd --no-headers | wc -l
# rebuild cadence/volume (CloudWatch Logs Insights on the apiserver log group):
#   fields @timestamp | filter @message like /Updating CRD OpenAPI spec because/
#   | stats count() by bin(30s)
```

**Apply** the scoped values (provider selection + MRAP) via the consuming
chart, let the providers reconcile, then deactivated MRs' CRDs stop being
served.

**After** (expect proportional drops):

```bash
kubectl get --raw /openapi/v2 | wc -c       # expect a large reduction
kubectl get crd --no-headers | wc -l        # expect (N − deactivated)
# re-run the CloudWatch stats — events/burst should fall proportionally,
# and apiserver recycle frequency should drop.
```

**Rollback** is a one-line edit: widen the `activate` globs or add the provider
entry back, commit, reconcile. No data is touched — deactivating an MR removes
its *served CRD*, not its underlying resources; re-activation restores it.

## Why this lives in the substrate

Provider scoping is a recurring impl every Crossplane consumer needs, not a
one-off. Expressing it as values-driven pleme-lib primitives (Pillar 12,
generation-over-composition) means each consumer declares its minimal set and
the cluster carries only the **union** of what's actually used — the broad,
unscoped default never re-appears.
