# lareira-github-webhook-flux

GitHub webhook → FluxCD reconcile bridge. Pattern #9 from the
[cookbook](https://github.com/pleme-io/theory/blob/main/WASM-PATTERNS.md).

Pushes propagate to the cluster in <10s instead of FluxCD's default
5min poll. KEDA HTTP add-on scales the receiver pod 0→N→0 with a
600s cooldown — webhook bursts settle to zero pods between bursts.

## GitHub setup

Per repository:
- Webhook URL → `https://git-webhook.<cluster>.<domain>/git-webhook`
- Content-type → `application/json`
- Secret → matches the cluster's `flux-system/github-webhook-secret`

## See also

- [`pleme-computeunit`](../pleme-computeunit/) — library chart
- Service shape with `breathability.enabled: true` — see
  [`theory/WASM-PACKAGING.md` §IV.2](https://github.com/pleme-io/theory/blob/main/WASM-PACKAGING.md)
