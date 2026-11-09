# lareira-github-webhook-flux

GitHub webhook → FluxCD reconcile bridge.

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
- Service shape with `breathability.enabled: true`
