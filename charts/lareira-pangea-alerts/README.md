# lareira-pangea-alerts

The **alert kind** of the `lareira-pangea-*` workspace family — the sibling of
[`lareira-pangea-dashboards`](../lareira-pangea-dashboards) (the dashboard kind).
From an `alerts:` values list it emits **one `PangeaAlert` CR per alert** — each
carrying inline Pangea Ruby that pangea-operator's `AlertController` evals to a
`Pangea::Alerts` AST and renders as a **VMRule** or a **PrometheusRule** (per
`backend`), stamped with a routing destination so Alertmanager sends it to the
right receiver.

An alert becomes **one entry in a values list** — no hand-authored rule YAML, no
`kubectl apply`. The same operator that manages cloud infrastructure manages
alerting.

## The pipeline this chart sits at the top of

```
alerts: values list  (this chart, the author surface)
   → PangeaAlert CR   (the typed border; spec.source.inline.ruby + spec.backend + spec.routing)
   → pangea-operator AlertController  (eval Ruby → Pangea::Alerts AST → VMRule | PrometheusRule)
   → the rendered rule, stamped `dest: <luis|akeyless|2f>`
   → Alertmanager routes it to the destination receiver
     (that receiver is wired cluster-side by lareira-respiro's OBSERVE stage)
```

## Per-alert values schema

Each entry in `alerts` is:

| Field | Required | Default | Meaning |
|---|---|---|---|
| `name` | yes | — | CR `metadata.name` (RFC 1123 DNS label). |
| `backend` | yes | — (vmrule is the recommended choice) | Render target: `vmrule` (VMRule) or `prometheusrule` (PrometheusRule). |
| `architecture` | yes | — | A `Pangea::Alerts::Library` mixin name, e.g. `GoldenSignals`. |
| `routing.destination` | yes | — | Routing destination: `luis` \| `akeyless` \| `2f`. |
| `id` | no | `name` | Stable alert identity (drives the AST id). |
| `params` | no | `{}` | YAML hash passed to the mixin. Shape is mixin-specific. |
| `message` | no | — | Version-tracking commit message. |
| `suspend` | no | `false` | When true, the operator skips synthesis + publish. |
| `namespace` | no | release namespace | Namespace for the emitted CR. |

## The AST-return contract

The rendered `spec.source.inline.ruby` for each alert is:

```ruby
require 'pangea-dashboards'
Pangea::Architectures::AlertWorkspace.render_ast(
  architecture: "GoldenSignals",
  params: JSON.parse(<<~'PANGEA_PARAMS', symbolize_names: true),
        {"name":"payments","job":"payments","namespace":"payments", ...}
  PANGEA_PARAMS
  id: "payments-golden",
)
```

The **last expression is a bare `render_ast(...)` call — NO `.to_json`**. The
operator evals the Ruby, gets a `Pangea::Alerts` AST, and renders it to a
`VMRule` (`spec.backend: vmrule`, the default) or a `PrometheusRule`
(`spec.backend: prometheusrule`). `params` is emitted as **JSON** (`toJson`) and
parsed back with `JSON.parse(<json>, symbolize_names: true)` — the
**JSON-through-Ruby** path, carried in a **single-quoted squiggly heredoc**
(`<<~'PANGEA_PARAMS'`) so any `{` `}` `(` `)` `"` `#{` inside a param value is
inert (no delimiter collision, no interpolation).

## Routing — one destination, one seam

`routing.destination` is the single knob. It is stamped **twice** through the
shared `pleme-lib.routing` seam (so this chart and `lareira-respiro` never fork
the mapping):

- as a **`dest: <v>` label** on the CR (and on every rule the operator renders), and
- as **`spec.routing.destination`** on the CR.

The three destinations:

| Destination | Behaviour | Receiver (wired by respiro) |
|---|---|---|
| `luis` | **WIRED** — the operator's own ntfy stream. | `webhookConfigs` → ntfy URL. `ntfyTopic` + `ntfyUrl` REQUIRED (empty `ntfyTopic` fails render). |
| `akeyless` | **INERT-IF-EMPTY** — the `dest: akeyless` seam matches, the sink is a later wiring. | `webhookConfigs: []` until `webhookUrl` is set. |
| `2f` | **INERT-IF-EMPTY** — same seam, distinct receiver name. | `webhookConfigs: []` until `webhookUrl` is set. |

This chart only declares the **destination**; the concrete receiver lives in
`lareira-respiro`'s OBSERVE stage (`observe.routing`), which drives the matching
`AlertmanagerConfig` from the same `pleme-lib.routing` helpers.

## Usage

```yaml
# HelmRelease values
alerts:
  - name: payments
    backend: vmrule
    architecture: GoldenSignals
    routing: { destination: luis }
    params:
      name: payments
      job: payments
      namespace: payments
  - name: ingress
    backend: prometheusrule
    architecture: Saturation
    routing: { destination: akeyless }
    params:
      name: ingress-nginx
      namespace: ingress-nginx
```

Two entries → two `PangeaAlert` CRs. Adding a third alert is a third list entry
— no template change.

## Worked example

[`examples/rio-golden-signals.values.yaml`](examples/rio-golden-signals.values.yaml)
is an applies-as-is example: **three** alert groups for rio workloads, one per
routing destination (`luis` / `akeyless` / `2f`), across both backends
(`vmrule` / `prometheusrule`). Render it locally:

```sh
helm template rio-alerts charts/lareira-pangea-alerts \
  -f charts/lareira-pangea-alerts/examples/rio-golden-signals.values.yaml
```

You get three `PangeaAlert` CRs (a CR each, not rendered rules — the operator
does the Ruby eval), labelled `dest: luis`, `dest: akeyless`, `dest: 2f`.

## Fail-guards (proven at render time)

- **Unknown `routing.destination`** → `helm template` fails
  (`pleme-lib.routing.destination` — plus the `values.schema.json` enum rejects
  it earlier).
- **Missing `backend`** → `helm template` fails with
  `alerts[<name>]: .backend is required (vmrule|prometheusrule)`.
- **`luis` with an empty `ntfyTopic`** → fails in the receiver seam
  (`pleme-lib.routing.receiver`), exercised where the receiver is materialized
  (`lareira-respiro` `observe.routing`) — a `luis` alert with nowhere to go is a
  bug, not a silent no-op.

## Convergence

Because each `PangeaAlert` is *reconciled* (not a one-shot apply), it inherits
the operator's guarantees: an unchanged alert never churns; a compile error
surfaces as `phase: Failed` + a typed condition; deleting the CR
garbage-collects its rendered rule; the rule re-converges after drift.
