# lareira-pvc-autoresizer

Helm chart deploying the
[`pvc-autoresizer`](https://github.com/pleme-io/programs/tree/main/pvc-autoresizer)
tatara-lisp program as a ComputeUnit on the cluster's
[`lareira-wasm-platform`](../lareira-wasm-platform/) runtime.

**Replaces** [`pleme-storage-elastic`](../pleme-storage-elastic/) —
same logic, expressed as a ~70-line tatara-lisp program instead of
a 280-line Rust binary + a 30 MiB OCI image.

## Install

```sh
helm install pvc-autoresizer ./charts/lareira-pvc-autoresizer \
  --namespace tatara-system \
  --set 'pleme-computeunit.enabled=true'
```

Or via FluxCD:

```yaml
# clusters/<name>/infrastructure/pvc-autoresizer/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: lareira-pvc-autoresizer
  namespace: tatara-system
spec:
  interval: 30m
  suspend: true                # default-OFF; flip to deploy
  chart:
    spec:
      chart: lareira-pvc-autoresizer
      version: "0.1.x"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
  values:
    pleme-computeunit:
      enabled: true
      config:
        # Per-cluster overrides; defaults are in the chart's values.yaml.
        triggerAt: 0.80
        maxSize: "100Gi"
        selector:
          matchLabels:
            breathable: "true"
```

## What gets emitted

```sh
$ helm template demo ./charts/lareira-pvc-autoresizer \
    --set 'pleme-computeunit.enabled=true' | grep -E '^kind:'
kind: ComputeUnit
kind: PrometheusRule
```

Two resources: the ComputeUnit (CR for the wasm-operator) + the
PrometheusRule (alerts on runaway expansion / ceiling reached).

## Default-OFF

`pleme-computeunit.enabled: false` — the chart renders nothing until
the operator flips it. Same invariant as every lareira-* chart in
this repo.
