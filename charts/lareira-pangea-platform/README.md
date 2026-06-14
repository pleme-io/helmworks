# lareira-pangea-platform

The **CORE** pangea platform chart. It deploys + fully manages
`pangea-operator` (as a subchart) and exposes a **single typed values
interface** that layers "workspaces of various kinds" onto the operator's CRD
vocabulary.

```
gems:       → ArchitectureGem CRs        (typed gem registry + smoke gate)
namespaces: → PangeaNamespace CRs        (state-storage isolation boundary)
workspaces: → WorkspaceCatalog + N InfrastructureTemplate CRs (policy cascade)
dashboards: → PangeaDashboard CRs        (dashboard-as-code, sidecar delivery)
```

A workspace **kind** is the unit of extension: a cloud-IaC kind, a DNS kind, a
secrets kind, and a dashboard kind all share this chart's shape and the
operator's CRD vocabulary — a new kind is a new values entry, never a new
control plane. See
[`pangea-operator/docs/DASHBOARD-AS-CODE.md`](../../../pangea-operator/docs/DASHBOARD-AS-CODE.md)
for the dashboard pipeline.

## Dependencies

| Chart | Repo | Role |
|---|---|---|
| `pleme-lib` | `file://../pleme-lib` | shared library templates |
| `pangea-operator` | `file://../pangea-operator` | the operator + all CRDs (subchart, `condition: pangea-operator.enabled`) |

```sh
helm dependency build charts/lareira-pangea-platform
```

The dashboards list is **pass-through-compatible** with the sibling
`lareira-pangea-dashboards` chart's helper. To keep the platform chart
standalone, `dashboards:` is rendered here directly as `PangeaDashboard` CRs;
a deployment that prefers the dedicated dashboards chart can disable the
operator subchart here and run both side by side.

## Values interface

### Top-level

| Key | Type | Default | Meaning |
|---|---|---|---|
| `pangea-operator.enabled` | bool | `true` | deploy the operator subchart. `false` → render only the CRD layer (operator deployed out-of-band). |
| `pangea-operator.*` | object | — | any `pangea-operator` chart value (e.g. `useEmbeddedRuby`, `image.tag`). |
| `namespace` | string | `""` | default namespace for **namespaced** CRs (`InfrastructureTemplate`, `PangeaDashboard`) when the CR sets none; falls back to the release namespace. Cluster-scoped CRs ignore it. |
| `commonLabels` | map | `{}` | labels merged onto every rendered CR. |
| `gems` | list | `[]` | → `ArchitectureGem` |
| `namespaces` | list | `[]` | → `PangeaNamespace` |
| `workspaces` | list | `[]` | → `WorkspaceCatalog` + `InfrastructureTemplate` |
| `dashboards` | list | `[]` | → `PangeaDashboard` |

Each list element maps 1:1 onto the matching operator CRD `spec`. The fields
below are the typed contract; unknown keys are rejected by
`values.schema.json` (`additionalProperties: false` on every element).

### `gems[]` → ArchitectureGem (cluster-scoped)

| Field | Req | Notes |
|---|---|---|
| `name` | ✓ | `metadata.name` |
| `gemName` | ✓ | Bundler / require name |
| `version` | ✓ | semver constraint (must be a **string** — quote `"0.x"`) |
| `source` | ✓ | `GemSource` — `gitRepository: { url, ref, path }` |
| `expectedClasses` | | FQ Ruby class names the gem exposes |
| `fixtures` | | smoke fixtures `[{ className, fixturePath, description }]` |
| `policy` | | `GemPolicy` — cascade root (`destroyProtection`, `driftReaction`, …) |
| `refreshInterval` | | e.g. `5m` |
| `suspend` | | default `false` |
| `labels` | | extra `metadata.labels` |

### `namespaces[]` → PangeaNamespace (cluster-scoped)

| Field | Req | Notes |
|---|---|---|
| `name` | ✓ | `metadata.name` |
| `backend` | ✓ | `BackendConfig` — `{ type: pg\|s3\|local, pg: { host, database, schemaPrefix, secretRef } }` |
| `description` | | |
| `defaultTags` | | map merged onto every resource |
| `defaultProviders` / `defaultComplianceProfiles` | | |
| `suspend` / `labels` | | |

### `workspaces[]` → WorkspaceCatalog + InfrastructureTemplate

Each entry renders **one** `WorkspaceCatalog` (cluster-scoped) plus **N**
`InfrastructureTemplate`s (namespaced). Templates are auto-labelled
`pangea.pleme.io/workspace=<name>` so they opt into the catalog's policy
cascade (gem → workspace → template → resource).

| Field | Req | Notes |
|---|---|---|
| `name` | ✓ | catalog `metadata.name` |
| `source` | ✓ | `WorkspaceSource` — `gitRepository: { url, ref, path }` (+ optional `path`) |
| `namespace` | | namespace its templates land in (defaults to `.Values.namespace`) |
| `requiredGems` | | gems that must reach `Loaded` before templates advance past `Verified` |
| `policy` | | `WorkspacePolicy` — `driftReaction`, `settlingPolicy`, `approvalRouting`, `reactive` |
| `suspend` / `labels` | | |
| `templates[]` | | child `InfrastructureTemplate`s (below) |

`workspaces[].templates[]`:

| Field | Req | Notes |
|---|---|---|
| `name` | ✓ | template `metadata.name` |
| `pangeaNamespace` | ✓ | state-isolation boundary (a `PangeaNamespace` name) |
| `source` | ✓ | `TemplateSource` — one of `inline` (Ruby) \| `configMapRef` \| `gitRepository` |
| `namespace` | | overrides the workspace namespace |
| `variables` / `variableRefs` | | template inputs |
| `autoApprove` / `destroyProtection` / `refreshInterval` | | |
| `executor` | | `magma` \| `tofu` |
| `policies` / `defaultDecision` | | per-resource policy rules |
| `settlingPolicy` / `reactivePolicy` | | drift / escalation policy |
| `importPolicy` / `importHints` | | adopt out-of-band resources |
| `providerCredentials` / `complianceProfiles` / `outputBindings` | | |
| `suspend` / `labels` | | |

### `dashboards[]` → PangeaDashboard (namespaced)

Dashboard-as-code. Each entry is one Grafana dashboard, declared as inline
Pangea Ruby that calls a `Pangea::Dashboards::Library` mixin (or a
`configMapRef`). The operator's `DashboardController` compiles the Ruby →
Grafana JSON and delivers it as a sidecar-labelled ConfigMap.

| Field | Req | Notes |
|---|---|---|
| `name` | ✓ | `metadata.name` |
| `source` | ✓ | `DashboardSource` (externally-tagged enum): `inline: { ruby }` \| `configMapRef: { name, key }` |
| `namespace` | | defaults to `.Values.namespace` |
| `folder` | | Grafana folder |
| `grafanaInstanceSelector` | | label selector for a target Grafana CR |
| `overwrite` | | default `true` |
| `extendModules` | | Ruby modules to extend before eval |
| `message` | | Grafana version-track commit message |
| `suspend` / `labels` | | |

## Example

```yaml
pangea-operator:
  enabled: true
  useEmbeddedRuby: true

namespace: pangea-system

gems:
  - name: pangea-architectures
    gemName: pangea-architectures
    version: "0.x"
    source: { gitRepository: { url: https://github.com/pleme-io/pangea-architectures, ref: main, path: lib } }
    expectedClasses: [Pangea::Architectures::CloudflareTunnel]
    policy: { destroyProtection: true, driftReaction: requireApproval }

namespaces:
  - name: rio-infra
    backend:
      type: pg
      pg: { host: pangea-database-rw.pangea-system.svc, database: pangea, secretRef: { name: pangea-db-credentials } }

workspaces:
  - name: rio-architectures
    namespace: rio-architectures
    source: { gitRepository: { url: https://github.com/pleme-io/k8s.git, ref: main, path: clusters/rio/architectures } }
    requiredGems: [pangea-architectures]
    policy: { driftReaction: autoApply }
    templates:
      - name: rio-arc-github
        pangeaNamespace: rio-infra
        executor: magma
        importPolicy: { autoOnConflict: true }
        source:
          inline: |
            template :rio_arc_github do
              self.extend(Pangea::Resources::Github)
            end

dashboards:
  - name: payments
    folder: rio
    source:
      inline:
        ruby: |
          Pangea::Dashboards::Library::WorkloadOverview
            .build(name: "payments", jobs: ["payments"])
            .then { |d| Pangea::Dashboards::Render::Grafana.render(d) }
```

A complete worked example lives at
[`tests/example-values.yaml`](./tests/example-values.yaml).

## Testing

```sh
helm dependency build .
helm lint .
helm template plat . -f tests/example-values.yaml
helm unittest .        # 4 suites, 22 tests
```

`tests/*_test.yaml` assert each values list renders the right CRD kind, count,
and fields (and that a missing required field fails render — caught both by
`values.schema.json` and the template's own `fail()` guards).
