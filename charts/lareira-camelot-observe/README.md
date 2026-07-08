# lareira-camelot-observe

> **Internal-review DRAFT.** The parameterized **enjulho observability CELL**.
> Not for merge — an internal-review draft on a scoop branch.

ONE values-parameterized chart that, keyed by `observe.env → camelot`, spawns the
**complete dashboards-as-code + alerts-as-code + routing structure** for the
camelot akeyless SaaS mesh (9 services) via `pangea-operator` CRDs. camelot is the
FedRAMP-Istio **instantiation** of the generic monitoring structure — a different
`observe.env` is a different value of this same chart.

## What it emits

All resources are `pangea.pleme.io/v1alpha1` CRs (no pods → **no breatheBand**):

| Range | CR | Architecture | Count (camelot) |
|---|---|---|---|
| `observe.services` | `PangeaDashboard` | `WorkloadOverview` | 9 |
| `observe.platformBoards` | `PangeaDashboard` | per-entry (akeyless-shaped) | 4 |
| `observe.services` (when `alerts.perService`) | `PangeaAlert` | `WorkloadBaseline` | 9 |

Every CR carries:
- the routing `dest: <destination>` label (via `pleme-lib.routing.labels`);
- the per-cell compliance overlay marker `compliance.pleme.io/overlay-*`
  (via `pleme-lib.overlay.dispatchAll`, shadow-first — annotations only).

Each `PangeaAlert` additionally sets `spec.routing.destination`; the concrete
Alertmanager receiver (ntfy for `luis`) is wired cluster-side by respiro.

## The parameterization (the deliverable)

```yaml
observe:
  env: camelot            # instantiation key (a different env = a different value)
  namespace: camelot      # CR + workload namespace
  folder: camelot         # Grafana folder
  datasource: vm          # metrics uid (matches lookout)
  logsDatasource: vlogs   # logs uid
  logsStream: '{namespace="camelot"}'
  routing: { destination: luis }   # luis|akeyless|2f ; camelot = luis (zero-egress ntfy)
  services:                # the 9-service topology (looped)
    - { name: auth,     job: auth,     port: 2770 }
    - { name: authcert, job: authcert, port: 2770 }
    - { name: bis,      job: bis,      port: 2771 }
    - { name: uam,      job: uam,      port: 2772 }
    - { name: uamop,    job: uamop,    port: 2772 }
    - { name: kfm,      job: kfm,      port: 2773 }
    - { name: sdr,      job: sdr,      port: 2774 }
    - { name: gator,    job: gator,    port: 2779 }
    - { name: logan,    job: logan,    port: 2780 }
  platformBoards:          # cross-service akeyless-shaped boards
    - { name: secrets-platform, architecture: SecretsPlatformOverview }
    - { name: auth-methods,     architecture: AuthMethodHealth }
    - { name: audit,            architecture: AuditExplorer }
    - { name: security-posture, architecture: SecurityPostureBoard }
  alerts: { perService: true, backend: vmrule }
compliance: { overlays: [fedramp-high], enforce: false }   # per-cell, shadow-first
# global.nodeSelector / global.tolerations / global.breathe inherited from the umbrella
```

### Per-service WorkloadOverview signals (presence + defects)

For each service the chart builds a 3-signal `StatusOverview` headline:

| Signal | Expr |
|---|---|
| presence | `min(up{job="<job>",namespace="<ns>"})` (crit at 0) |
| restarts | `increase(kube_pod_container_status_restarts_total{namespace="<ns>",pod=~"<name>.*"}[1h])` |
| OOM | `kube_pod_container_status_last_terminated_reason{namespace="<ns>",reason="OOMKilled",pod=~"<name>.*"}` |

`params` is emitted as JSON inside a single-quoted squiggly heredoc
(`<<~'PANGEA_PARAMS'`) and parsed in Ruby via `JSON.parse(…, symbolize_names:
true)` — the JSON-through-Ruby path, so any `{ } ( ) "` in a signal expr is inert.

## Isolation, breathe, compliance — by construction

- **No hardcoded `nodeSelector` / `tolerations`.** This cell emits only CRs;
  nothing is scheduled. camelot node-isolation + breathe come from the umbrella
  `global`, inherited — never restated here.
- **No breatheBand.** There is no pod-bearing template, so no breatheBand is
  carried (noted, per the cell's CR-only shape).
- **Compliance is per-cell** (`compliance.overlays`), not a global seam.
  `fedramp-high` cascades `fedramp-moderate` + `fedramp-low`; shadow-first
  (`enforce: false`) stamps the marker without running chart-time validators.

## Dependencies

`pleme-lib >= 0.37.0` (`file://../pleme-lib`) — for the `pleme-lib.routing.*`
destination seam and the `pleme-lib.overlay.*` compliance seam only. The
PangeaDashboard / PangeaAlert CRs are hand-authored here, mirroring
`lareira-pangea-dashboards` + `lareira-pangea-alerts`.

## Render

```bash
helm dependency update charts/lareira-camelot-observe
helm template camelot charts/lareira-camelot-observe \
  -f charts/lareira-camelot-observe/examples/camelot.values.yaml
```

Expect 9 + 4 `PangeaDashboard` + 9 `PangeaAlert`, every one carrying `dest: luis`
and `compliance.pleme.io/overlay-fedramp-high`. A bad `observe.routing.destination`
fails render via the `pleme-lib.routing` enum guard.

## Blocker for reconcile

These CRs only become live dashboards/alerts when **pangea-operator is running
in the camelot namespace** with `pangea-dashboards` (incl. the enjulho Library
mixins + `AlertWorkspace`) on its `$LOAD_PATH`. Absent the operator, the chart
renders valid CRs that sit `Pending` — the cell declares the observability
structure; the operator realizes it.
