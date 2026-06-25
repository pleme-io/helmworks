# lareira-tap-stack

The **thin per-tap composition umbrella**. It presents the **tap-cell**
vocabulary (`tap.*`) and composes the already-shipped pipeline charts into one
per-tap unit. It owns **no new algebra** — every rendered document comes from a
subchart; this chart only translates the tap intent into each subchart's native
values surface.

```
tap.*  (this chart, the author surface)
  ├─▶ lareira-respiro            — Vector ingest → NATS JetStream 0-scale
  │                               → KEDA 0→N → breathe bands → vlogs sink
  └─▶ lareira-pangea-dashboards  — optional per-tap Grafana dashboards
        … points at (never bundles) the SHARED victoriaops store
        (lareira-vm-stack + lareira-victoria-logs, deployed once, separately).
```

## The store-up / processing-breathes split

A **tap breathes** (per-tap, scale-to-zero, ephemeral processing); the
**store is up** (shared, durable, deployed once). This umbrella is the
*processing* half only. It deliberately does **not** depend on `lareira-vm-stack`
or `lareira-victoria-logs` — the VictoriaLogs sink endpoint it ships
(`http://victoria-logs.monitoring.svc:9428`, via the respiro `sink.kind=vlogs`)
targets the separately-deployed shared store.

## The tap-cell

A *tap* is one named `ingest → breathe → sink` cell. Its canonical name is a
typed 6-tuple — the stream / consumer / band identity all derive from it:

```
tap-<datakind>-<tenant>-<env>-<cloud>-<region>
```

| Token | Meaning | Example |
|---|---|---|
| `datakind` | class of data the tap carries | `archive`, `audit`, `events`, `metrics` |
| `tenant`   | owning tenant / product | `acme`, `pleme` |
| `env`      | environment | `prod`, `staging`, `dev` |
| `cloud`    | cloud / substrate | `aws`, `gcp`, `rio` |
| `region`   | locality | `us-east-1`, `bristol-tn` |

`tap.name` is that full string; `templates/_helpers.tpl`'s
`lareira-tap-stack.streamName` derives the NATS-token-safe JetStream stream name
from it (via Helm string-pipeline ops — ★★ TYPED EMISSION, never a `printf` of
config syntax).

## Default-off

`tap.enabled=false` (the default) renders **zero documents** — defense in depth:

- `lareira-respiro.respiro.enabled` defaults **false** ⇒ the respiro spine
  renders 0 docs; the dep `condition: tap.respiro.enabled` additionally drops the
  subchart for a dashboards-only tap.
- `lareira-pangea-dashboards` is gated by `condition: tap.dashboards.enabled`
  (default false) and ships an empty `dashboards: []` (0 CRs).

A tap that ships before its values are wired is a safe no-op (auto-release stays
green).

## Activating a tap-cell

> **Helm note:** a parent chart cannot compute a subchart's values at render
> time (Helm resolves subchart values *before* templating). Enabling a tap is a
> direct value edit of the `lareira-respiro.*` passthrough.

```yaml
tap:
  enabled: true
  datakind: audit
  name: tap-audit-acme-prod-aws-us-east-1
  respiro: { enabled: true }
  dashboards: { enabled: false }

lareira-respiro:
  respiro:
    enabled: true                       # the breathing-pipeline master switch
    ingest:
      source: { kind: kubernetes_logs }  # or http | socket
    stream:
      name: TAP_AUDIT_ACME_PROD_AWS_US_EAST_1
      subjects: ["tap_audit.>"]
      consumer: { name: tap-audit }
    consumers: { min: 0, max: 8 }        # scale-0→N
    breathe:  { enabled: true, dryRun: true }  # SHADOW-first
    sink:     { kind: vlogs }            # → the SHARED VictoriaLogs store
```

A dashboards-only tap sets `tap.respiro.enabled=false`,
`tap.dashboards.enabled=true`, and populates
`lareira-pangea-dashboards.dashboards`.

## Subchart value-passing wiring

| Parent key | → Subchart | Effect |
|---|---|---|
| `lareira-respiro.respiro.*` | `lareira-respiro` | drives the 5-stage breathing spine |
| `lareira-pangea-dashboards.dashboards` | `lareira-pangea-dashboards` | one PangeaDashboard CR per entry |
| `tap.respiro.enabled` (condition) | `lareira-respiro` | include/exclude the subchart |
| `tap.dashboards.enabled` (condition) | `lareira-pangea-dashboards` | include/exclude the subchart |

## What this chart is NOT

- **Not** the store. `lareira-vm-stack` / `lareira-victoria-logs` are a separate,
  shared deployment.
- **Not** a source of new resources. Zero bespoke templates in M0 — only
  `_helpers.tpl` + `NOTES.txt`.

## TODO / deferred slots

- **Glue-driven stream identity** — M0 sets `lareira-respiro.respiro.stream.*`
  by hand; a future milestone could ship a typed `(deftap …)` form that emits
  the full `lareira-respiro.*` passthrough from the 6-tuple, removing the manual
  edit (Helm cannot do this parent-side; it belongs upstream in the tap authoring
  vocabulary).
- **Per-datakind sink routing** — `tap.datakind` could select the sink endpoint
  / retention tier automatically once the respiro sink surface grows the typed
  arms (`vm | grafana | splunk | …` are later respiro milestones).
