# lareira-openclaw-stack

Umbrella chart composing the openclaw skill-store ecosystem:

| Sub-chart | Service | Default |
|---|---|---|
| `pki`     | `lareira-openclaw-pki`     | enabled |
| `store`   | `lareira-openclaw-store`   | enabled |
| `scanner` | `lareira-openclaw-scanner` | enabled |

Every sub-chart inherits the `fedramp-high` overlay via
`pleme-microservice`; the umbrella adds release-lifecycle composition
and per-sub-chart toggles.

## Cluster prerequisites

This chart presumes a FedRAMP-High-shaped cluster. Specifically:

| Capability | Provider |
|---|---|
| Tameshi admission gate | `sekiban` chart deployed |
| Compliance overlay enforcement | `pleme-admission-policies` with `overlays={fedramp-high}` |
| Image admission rules | `lareira-kyverno` |
| Encrypted PVC class | StorageClass named `encrypted-default` |
| OIDC provider | `authentik` (saguão fleet IdP) |
| External Secrets | `external-secrets-operator` + `cluster-secret-store` |
| Secret materialization | `cofre`-managed Akeyless / SOPS / Vault entry for `openclaw/publisher-pki/org-seed` |

The cluster floor (FedRAMP-compliant VPC, KMS, Flow Logs, GuardDuty,
Config Rules, etc.) lives in `pangea-architectures` —
`lib/pangea/architectures/generated/compliance/fedramp_high.rb`.

## Install

```bash
# Pin every sub-chart's image digest at install time. CI pipeline
# normally materializes this into a release-specific values overlay.
helm install openclaw oci://ghcr.io/pleme-io/charts/lareira-openclaw-stack \
  --namespace openclaw \
  --create-namespace \
  --set "pki.pleme-microservice.image.tag=sha256:<pki-digest>" \
  --set "store.pleme-microservice.image.tag=sha256:<store-digest>" \
  --set "scanner.pleme-microservice.image.tag=sha256:<scanner-digest>"
```

## Disable a sub-chart

```bash
# Deploy only store + scanner (using a central PKI deployed elsewhere).
helm upgrade openclaw … --set pki.enabled=false
```

## Compliance proof surface

The mechanical chain (chart → admission → cluster):

```
values.yaml
  compliance.overlays: [fedramp-high]   ──┐
                                          ├─→ pleme-lib overlay registry
                                          │     • template-time fail() validators
                                          │     • Kyverno ClusterPolicies
                                          │     • compliance-manifest ConfigMap
                                          │     • compliance.pleme.io/* labels
                                          ▼
                                    pleme-admission-policies
                                          ▼
                                    sekiban admission webhook
                                          ▼
                                    cluster-side enforcement
```

A control either passes through the entire chain or the stack fails to
deploy. There is no half-compliant state.

## See also

- `pleme-io/helmworks/docs/COMPLIANCE-PROOF.md` — the proof
- `pleme-io/helmworks/docs/COMPLIANCE-OVERLAYS-DESIGN.md` — design spec
- `pleme-io/theory/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md` — frame
- `pleme-io/skills/compliant-skill-store/SKILL.md` — author/operator workflow
