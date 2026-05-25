# pleme-lava-operator

Helm chart for `pleme-io/lava-operator` — typed Kubernetes
controller for the `LavaArchitecture` CRD. Embedded magma + drift
detection + OutcomeChain + AnomalyController + 7-beat Viggy tick.

## Authoring source

This chart is **NOT hand-authored YAML**. Its source of truth is a
single tatara-lisp form at [`_source/chart.tlisp`](./_source/chart.tlisp):

```lisp
(deflava-chart pleme-lava-operator
  :version "0.1.0"
  :app-version "0.5.0"
  :description "..."
  :type application
  :values    (...)
  :manifests ((manifest deployment ...)
              (manifest service ...)
              ...))
```

The renderer (`lava-chart-cli`, shipped by `pleme-io/lava-chart`)
re-derives `Chart.yaml`, `values.yaml`, and every file under
`templates/` from this one source.

### Regenerate

```bash
# 1. Re-render Chart.yaml + values.yaml + templates/ from .tlisp source
nix run github:pleme-io/lava-chart -- \
  render charts/pleme-lava-operator/_source/chart.tlisp \
         charts/pleme-lava-operator

# 2. Re-render CRDs from the operator binary (Helm v3 auto-applies
#    `crds/` content on install — but not on upgrade — by convention)
nix run github:pleme-io/lava-operator -- crds \
  > charts/pleme-lava-operator/crds/lava-operator-crds.yaml
```

Or, if both binaries are on PATH:

```bash
lava-chart-cli render _source/chart.tlisp .
lava-operator crds > crds/lava-operator-crds.yaml
```

The CRDs surface (`LavaArchitecture`, `RemediationPolicy`,
`LavaArchitectureDependency`) comes from the **same Rust types the
operator uses to reconcile** — there's no separate hand-authored CRD
YAML. Edit the kube-rs `#[derive(CustomResource)]` shapes in
`pleme-io/lava-operator/src/controller.rs` and re-render.

## Install

```bash
helm install lava-operator oci://ghcr.io/pleme-io/charts/pleme-lava-operator
```

## Values

| key | default | purpose |
|---|---|---|
| `replicaCount` | `1` | Operator replica count |
| `image.repository` | `ghcr.io/pleme-io/lava-operator` | Container image |
| `image.tag` | `v0.5.0` | Image tag (matches lava-operator version) |
| `executor.embedded.enabled` | `true` | Run magma in-process (default) |
| `executor.remote.enabled` | `false` | Use remote magma executor instead |
| `outcomeChain.sink.kind` | `filesystem` | OutcomeChain persistence |
| `outcomeChain.sink.path` | `/var/lib/lava-operator/chains` | Sink path |
| `outcomeChain.signing.kind` | `ed25519` | Receipt signing scheme |
| `outcomeChain.signing.secretRef` | `lava-operator-signing-key` | K8s Secret holding the Ed25519 key |
| `drift.scanIntervalSeconds` | `60` | Periodic drift scan cadence |
| `drift.cosmeticAttributePrefixes` | `[tags., labels.]` | Attribute prefixes that demote Functional → Cosmetic |
| `anomaly.defaultPolicy.cosmetic` | `Alert` | Default remediation for cosmetic drift |
| `anomaly.defaultPolicy.functional` | `AutoCorrect` | Default for functional |
| `anomaly.defaultPolicy.critical` | `RequireApproval` | Default for critical |
| `viggy.tickBudgetMs` | `30000` | Max time one Viggy tick may take |
| `viggy.requeueOnFailureSeconds` | `60` | Requeue delay on tick failure |
