# lareira-fleet-programs

Declare every WASM/WASI program a cluster runs in **one Helm release**.

The user-facing answer to *"pull programs from git and just run them
on the cluster — perfect state with a consistent system"*: a single
values.yaml lists the programs (each as a tatara-lisp-script git URL +
trigger + capabilities + config), and FluxCD reconciles the cluster's
ComputeUnit set to match. Add a program → append a list entry. Remove
→ delete the entry. Bump version → change the `?ref=` tag.

## How it differs from per-program lareira-* charts

| | Per-program chart (e.g. lareira-pvc-autoresizer) | This chart |
|---|---|---|
| Programs in one Helm release | 1 | N |
| Operator adds a program | New HelmRelease | Append to list |
| Removes a program | Delete HelmRelease | Delete list entry |
| Cluster-wide version bump | Edit each chart's values | Edit one file |
| Use when | Stable per-program defaults; chart-version-pinned | Cluster-wide program inventory |

Both shapes coexist. Use per-program charts for stable platform
infrastructure (where the chart's defaults rarely change). Use this
fleet-programs chart for the cluster's growing inventory of
application-level programs.

## Example: rio cluster's program inventory

```yaml
# clusters/rio/programs/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: rio-fleet-programs
  namespace: tatara-system
spec:
  chart:
    spec:
      chart: lareira-fleet-programs
      version: "0.1.x"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
  values:
    enabled: true

    programs:
      - name: pvc-autoresizer
        module: { source: github:pleme-io/programs/pvc-autoresizer/main.tlisp?ref=v0.1.0 }
        trigger: { cron: "*/5 * * * *" }
        capabilities:
          - kube-pvc-list
          - kube-pvc-patch
          - prom-query@vmsingle-vm.monitoring.svc:8429
        config:
          triggerAt: 0.80
          maxSize: "100Gi"

      - name: dns-reconciler
        module: { source: github:pleme-io/programs/dns-reconciler/main.tlisp?ref=v0.1.0 }
        trigger:
          watch:
            crd: dns.pleme.io/DnsReconciler
        capabilities:
          - kube-cr-watch@dns.pleme.io/dnsreconcilers
          - kube-cr-watch@v1/services
          - kube-secret-read@dns-system/cloudflare-pangea
          - http-out:api.cloudflare.com

      - name: github-webhook-flux
        module: { source: github:pleme-io/programs/github-webhook-flux/main.tlisp?ref=v0.1.0 }
        trigger:
          service:
            port: 8080
            paths: ["/git-webhook"]
            hosts: ["git-webhook.flux-system.svc.cluster.local"]
            breathability: { enabled: true, cooldownPeriod: 600 }
        capabilities:
          - http-in:0.0.0.0:8080
          - kube-resource-list@source.toolkit.fluxcd.io/gitrepositories
          - kube-resource-patch@source.toolkit.fluxcd.io/gitrepositories
          - kube-secret-read@flux-system/github-webhook-secret

      - name: thumbnail-fn
        module: { source: github:pleme-io/programs/thumbnail-fn/main.tlisp?ref=v0.1.0 }
        trigger:
          event: { source: "nats:rio.events.photo.uploaded", batch_size: 10 }
        capabilities:
          - nats-subscribe@rio.events.photo.uploaded
          - s3-read@rio-photos-originals
          - s3-write@rio-photos-thumbnails
        config:
          variants:
            - { name: small,  width: 200,  height: 200,  format: webp }
            - { name: medium, width: 800,  height: 800,  format: webp }
            - { name: large,  width: 1920, height: 1920, format: webp }
```

That's the cluster's complete program inventory in one file.

## Validation

The chart fails fast at render-time on:
- entry without `name`
- entry without `module.source` or `module.oci`
- entry with zero or multiple trigger shapes
- entry with unknown event-source prefix

This makes operator mistakes (typo in trigger field, missing capability)
fail at `helm template` time, before the cluster ever sees a malformed CR.

## What renders per program

Same set as `pleme-computeunit` for a single program — see
[`pleme-computeunit/README.md`](../pleme-computeunit/README.md) for
the detail. Per-shape: ComputeUnit (always) + Service +
HTTPScaledObject (service shape) + KEDA ScaledObject (function shape)
+ policy CR (controller shape, opt-in) + PrometheusRule (any shape,
opt-in).

## See also

- [`theory/FLEET-DECLARATION.md`](https://github.com/pleme-io/theory/blob/main/FLEET-DECLARATION.md) — the design
- [`pleme-computeunit`](../pleme-computeunit/) — per-program library chart
- [`theory/META-FRAMEWORK.md`](https://github.com/pleme-io/theory/blob/main/META-FRAMEWORK.md) — the meta-framework
