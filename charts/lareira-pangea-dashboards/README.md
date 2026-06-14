# lareira-pangea-dashboards

The **dashboard kind** of the `lareira-pangea-*` workspace family. From a
`dashboards:` values list it emits **one `PangeaDashboard` CR per dashboard** —
each carrying inline Pangea Ruby that pangea-operator's `DashboardController`
compiles to Grafana JSON and delivers as a sidecar-labelled ConfigMap.

A dashboard becomes **one entry in a values list** — no hand-authored dashboard
JSON, no `kubectl apply` of a ConfigMap, no Grafana UI clicking. The same
operator that manages cloud infrastructure manages observability.

Full design: [`pangea-operator/docs/DASHBOARD-AS-CODE.md`](../../../pangea-operator/docs/DASHBOARD-AS-CODE.md).
Component vocabulary: `pangea-dashboards/docs/COMPONENT-LIBRARY.md`.

## The pipeline this chart sits at the top of

```
dashboards: values list  (this chart, the author surface)
   → PangeaDashboard CR   (the typed border; spec.source.inline.ruby)
   → pangea-operator DashboardController  (eval Ruby → Grafana JSON)
   → sidecar-labelled ConfigMap (grafana_dashboard="1", grafana_folder=<folder>)
   → Grafana (grafana.quero.cloud) — live + converged
```

## Per-dashboard values schema

Each entry in `dashboards` is:

| Field | Required | Default | Meaning |
|---|---|---|---|
| `name` | yes | — | CR `metadata.name` (RFC 1123 DNS label). |
| `architecture` | yes | — | A `Pangea::Dashboards::Library` mixin name, e.g. `WorkloadOverview`. |
| `folder` | no | top-level `folder` (then `rio`) | Grafana folder for this dashboard. |
| `params` | no | `{}` | YAML hash passed to the mixin. Shape is mixin-specific. |
| `message` | no | — | Grafana version-tracking commit message. |
| `suspend` | no | `false` | When true, the operator skips synthesis + publish. |
| `namespace` | no | release namespace | Namespace for the emitted CR. |

Top-level `folder` (default `rio`) is the fallback folder for any dashboard that
doesn't set its own.

## The inline-ruby template approach

`params` is emitted as **JSON** (`toJson`) and parsed back in Ruby with
`JSON.parse(<json>, symbolize_names: true)` — the **JSON-through-Ruby** path. It
avoids Ruby-hash-literal escaping entirely, and the JSON is carried in a
**single-quoted squiggly heredoc** (`<<~'PANGEA_PARAMS'`) so any `{` `}` `(` `)`
`"` `#{` inside a param value is inert (no delimiter collision, no interpolation).

The rendered `spec.source.inline.ruby` for each dashboard is:

```ruby
require 'pangea-dashboards'
Pangea::Architectures::GrafanaDashboardWorkspace.render_json(
  architecture: "WorkloadOverview",
  params: JSON.parse(<<~'PANGEA_PARAMS', symbolize_names: true),
        {"name":"payments","jobs":["payments"],"namespace":"payments", ...}
  PANGEA_PARAMS
  folder: "rio",
)
```

## Usage

```yaml
# HelmRelease values
folder: rio
dashboards:
  - name: payments
    architecture: WorkloadOverview
    params:
      name: payments
      jobs: [payments]
      namespace: payments
      rate_metric: http_requests_total
  - name: ingress
    folder: rio-platform
    architecture: WorkloadOverview
    params:
      name: ingress-nginx
      jobs: [ingress-nginx]
      namespace: ingress-nginx
```

Two entries → two `PangeaDashboard` CRs. Adding a third dashboard is a third
list entry — no template change.

## Worked example — a real rio dashboard

[`examples/rio-workload-overview.values.yaml`](examples/rio-workload-overview.values.yaml)
is an applies-as-is example: one `WorkloadOverview` dashboard for rio's
**tend-operator** (the fleet flake-update controller), built from its actual
`tend_operator_*` metric families (exposed at
`tend-operator.tend-system:9090/metrics`, scraped by vmagent). It supplies the
`WorkloadOverview`-required `params` (`id` / `name` / `datasource` / `jobs` /
`signals`) and intentionally omits the RED golden-signals row — tend-operator is
an event-driven reconcile controller, not a request-serving HTTP workload, so it
exports no `*_requests_total` / `*_duration_seconds_bucket`. Render it locally:

```sh
helm template tend-dash charts/lareira-pangea-dashboards \
  -f charts/lareira-pangea-dashboards/examples/rio-workload-overview.values.yaml
```

You get one `PangeaDashboard` named `tend-operator` whose
`spec.source.inline.ruby` carries the `GrafanaDashboardWorkspace.render_json`
call (a CR, not a rendered dashboard — the operator does the Ruby eval).

## Wire it on rio (FluxCD HelmRelease)

> **Don't `kubectl apply` / `helm install` against rio.** Per the rio cluster
> doctrine (declare + observe only), you ship a dashboard by *committing* a
> HelmRelease and letting FluxCD reconcile it. The snippet below is what you
> commit — **it is not applied here.**

The rio dashboards kustomization path already exists at
[`k8s/clusters/rio/apps/dashboards/`](../../../k8s/clusters/rio/apps/dashboards/)
(wired into Flux by `flux-kustomizations/apps-dashboards.yaml`, which
`dependsOn: infrastructure-pangea` so the `PangeaDashboard` CRD is served
first). Today that directory holds the hand-authored `tend-operator.yaml`
CR; the dashboard-as-code path replaces hand-authored CRs with a HelmRelease
that *renders* them from values. Add a `release.yaml` under that directory and
reference it from the directory's `kustomization.yaml`:

```yaml
# k8s/clusters/rio/apps/dashboards/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: pangea-dashboards
  namespace: tend-system
spec:
  interval: 30m
  suspend: false
  dependsOn:
    # The PangeaDashboard CRD this chart emits is served by the operator.
    - name: pangea-operator
      namespace: monitoring
  chart:
    spec:
      chart: lareira-pangea-dashboards
      version: "0.1.x"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
        namespace: flux-system
  install: { remediation: { retries: 3 } }
  upgrade: { remediation: { retries: 3 } }
  # Inline the example values (or point valuesFrom / a kustomize patch at them).
  values:
    folder: rio-fleet
    dashboards:
      - name: tend-operator
        folder: rio-fleet
        architecture: WorkloadOverview
        message: "rio tend-operator — fleet update controller (WorkloadOverview)"
        params:
          id: rio-tend-operator
          name: tend-operator
          datasource: vm
          jobs: [tend-operator]
          namespace: tend-system
          signals:
            - { name: "Reconcile errors (1h)", expr: 'sum(increase(tend_operator_reconcile_errors_total[1h]))', warn: 1, crit: 5 }
            - { name: "Applies failed (24h)",   expr: 'sum(increase(tend_operator_applies_total{outcome="failed"}[24h]))', warn: 1, crit: 3 }
            - { name: "Gate failures (1h)",     expr: 'sum(increase(tend_operator_gates_total{outcome="failed"}[1h]))', warn: 1, crit: 5 }
```

```yaml
# k8s/clusters/rio/apps/dashboards/kustomization.yaml
resources:
  - release.yaml
  # - tend-operator.yaml   # remove once pangea-dashboards owns this dashboard
```

Commit; FluxCD reconciles `apps-dashboards`; the operator synthesizes the CR;
the Grafana sidecar loads the ConfigMap.

### Observe convergence

```sh
# Phase Pending → Synthesizing → Ready (Failed on compile error)
kubectl get pangeadashboard -n tend-system

# Typed conditions + the compile error (if any) + the dashboard uid
kubectl get pangeadashboard -n tend-system tend-operator -o yaml | yq '.status'
```

Or query the **grafana-rio MCP** (`search_dashboards "tend operator"`,
`get_dashboard_by_uid rio-tend-operator`). `phase: Failed` ⇒ read
`status.error` (unknown `architecture:`, or a `WorkloadOverview` kwarg
validation like "rate_metric and latency_metric must be given together"). See
the `dashboard-as-code` skill for the full failure catalogue.

## Convergence

Because each `PangeaDashboard` is *reconciled* (not a one-shot apply), it
inherits the operator's guarantees: the `sourceHash` diff-gate means an
unchanged dashboard never churns; a compile error surfaces as `phase: Failed` +
a typed condition; deleting the CR garbage-collects its ConfigMap; the dashboard
re-converges after drift.

## Test

```sh
cd charts/lareira-pangea-dashboards
helm unittest -f "../../tests/lareira-pangea-dashboards/*_test.yaml" .
```
