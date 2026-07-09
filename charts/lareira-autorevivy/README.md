# lareira-autorevivy

**Autorevivy — the system that watches systems, and keeps them alive.**
The camelot-scoped self-maintenance layer.

> **camelot-scoped now; fleet-wide is the destination.** `spec.scope` is the gate —
> the shipped controller accepts `camelot` only. Fleet-wide redistribution
> (`autorevivy-admission` + `pleme-lib global.autorevivy`, the breathe-admission
> pattern one layer up) is the named destination, **off** outside camelot.

Canonical doctrine: [`theory/AUTOREVIVY.md`](https://github.com/pleme-io/theory/blob/main/AUTOREVIVY.md).
Operator handle: the `/autorevivy` skill (folds the former `/breathability` +
`/auto-remediation-engine`).

## What it is

One concept for self-maintenance = **CLEAN + DEFEND + PROTECT**, live-tuned in real
time, escalating-by-discoverability. It owns **minimal new algebra** — a composition
index over breathe + sarar + tendril + Viggy + shigoto + cron + super-cache-ci +
tameshi. This chart ships the **declarative surface**; it references the composed
primitives' CRs rather than re-declaring them.

## What the chart ships

| Artifact | Tier |
|---|---|
| `crds/autorevivy.yaml` — the `Autorevivy` CRD (`autorevivy.pleme.io/v1`) | **deployable** |
| `templates/autorevivy.yaml` — one `Autorevivy` CR rendered from `values.autorevivy` | **deployable** |
| `templates/rbac.yaml` — read the estate, patch only the Autorevivy status + breathe bands (declare-and-observe; no raw mutation) | **deployable** |
| `templates/deployment.yaml` — the coordinator controller | **STUB / LiveTODO** — `controller.enabled=false` by default |
| `templates/breatheband.yaml` — the controller dogfoods a band (explicit `dryRun`) | rendered only when `controller.enabled` |

## Tier-honest

- **Shipped:** the CRD + CR + RBAC (a real, deployable declarative surface).
- **DESIGN / LiveTODO (do not round up):** the closed coordinator controller
  (`controller.enabled=false`) — the loop runs **manually** today over the shipped
  MCPs (breathe / grafana / engenho / escuta). The `Discoverability` auto-selector and
  the `(defautorevivy)` triplet are net-new. The fleet-wide `scope: fleet` path is the
  destination, refused by the shipped controller.

## Install (into camelot)

Reconciled by pangea-operator / FluxCD into Camelot, peer of
`lareira-breathe-observability`. Carries the camelot posture (`nodeSelector
{role: camelot}` + `camelot-only` toleration, `dryRun: true` default).
