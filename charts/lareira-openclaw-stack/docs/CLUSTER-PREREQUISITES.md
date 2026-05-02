# openclaw stack — cluster prerequisites

Checklist for the cluster operator before installing
`lareira-openclaw-stack`. Each prerequisite is enforced by the chart at
template render or admission time; missing prerequisites produce clear
error messages, not silent failures.

## Required (chart will refuse without these)

### 1. FedRAMP-High-shaped cluster floor
**Verified by:** the deploy succeeding (the cluster admin establishes
this; the chart consumes it).

| Element | Source |
|---|---|
| VPC + subnets + flow logs + KMS + GuardDuty + Config | `pangea-architectures/lib/pangea/architectures/generated/compliance/fedramp_high.rb` |
| Encrypted-at-rest StorageClass named `encrypted-default` | cluster operator (or `lareira-openclaw-store/values.yaml` overrides `persistence.sqlite.storageClass`) |

### 2. Tameshi admission gate
**Verified by:** sekiban CRDs accepted at install.

```bash
# Required CRDs.
kubectl get crd certifications.sekiban.pleme.io
kubectl get crd compliancepolicies.sekiban.pleme.io
kubectl get crd signaturegates.sekiban.pleme.io
```

If missing, install the `sekiban` Helm chart:
```bash
helm install sekiban oci://ghcr.io/pleme-io/charts/sekiban \
  --namespace sekiban-system --create-namespace
```

### 3. Compliance overlay enforcement
**Verified by:** Kyverno ClusterPolicies present.

```bash
kubectl get clusterpolicy pleme-overlay-fedramp-moderate
kubectl get clusterpolicy pleme-overlay-fedramp-high
```

If missing, install:
```bash
helm install pleme-policies oci://ghcr.io/pleme-io/charts/pleme-admission-policies \
  --namespace kyverno-system --create-namespace \
  --set 'compliance.overlays={fedramp-high}'
```

### 4. External Secrets Operator
**Verified by:** ExternalSecret reaches `Synced`.

```bash
kubectl get crd externalsecrets.external-secrets.io
kubectl get clustersecretstore cluster-secret-store
```

If missing:
```bash
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace
```
Then create a `ClusterSecretStore` named `cluster-secret-store` pointing
at the org's Akeyless / SOPS / Vault backend (see
`pleme-io/cofre/docs/backends.md`).

### 5. cofre-materialized org-seed
**Verified by:** the chart's `ExternalSecret` reaching `Synced` and
backing the K8s Secret `openclaw-pki-org-seed` with key `hex`.

```bash
# Generate + apply once per cluster.
SEED=$(openssl rand -hex 32)
cat <<EOF > /tmp/org-seed.yaml
- backend: akeyless
  path: openclaw/publisher-pki/org-seed
  property: hex
  value: ${SEED}
EOF
cofre apply --manifest /tmp/org-seed.yaml
shred -uvz /tmp/org-seed.yaml
```

The chart's ExternalSecret references `openclaw/publisher-pki/org-seed`
in the configured backend. Override the key path via
`pki.orgSeed.externalSecret.remoteRef.key`.

### 6. Persistence backend (store)

The store's merkle ledger is stateful. Two supported modes:

#### sqlite (default — single-node demos / homelab)
A PVC bound to `encrypted-default` StorageClass. Multi-replica reads
work; production should use postgres.

#### postgres (HA / production)

```bash
# Required: a CloudNativePG cluster reachable as cnpg-openclaw-rw.openclaw.svc.
helm install cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace
kubectl apply -n openclaw -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: { name: cnpg-openclaw }
spec:
  instances: 3
  storage: { size: 50Gi, storageClass: encrypted-default }
  bootstrap: { initdb: { database: openclaw_store, owner: openclaw } }
EOF

# Required: SOPS-encrypted Secret with the postgres password.
sops -e secrets/openclaw-store-postgres.yaml > secrets/openclaw-store-postgres.enc.yaml
```

Then set in chart values:
```yaml
store:
  persistence:
    backend: postgres
    postgres:
      host: cnpg-openclaw-rw.openclaw.svc.cluster.local
      database: openclaw_store
      sslMode: require
      secretRef: { name: openclaw-store-postgres, passwordKey: password }
```

## Required for the production posture

### 7. Authentik OIDC reachable
The fedramp-high overlay's `compliance.authn.oidc` declares Authentik
as the IdP. The store API should be fronted by an authentik-enforced
gateway.

### 8. Saguão fleet identity (optional but recommended)
If the cluster is part of the saguão fleet, the store hostname
`store.<cluster>.<location>.quero.cloud` is allocated by `passaporte`
and gated by `vigia` automatically. See `theory/SAGUAO.md`.

### 9. Encrypted log pipeline
Vector → VictoriaLogs (homelab) or Vector → Splunk HEC (SaaS). Required
by AU-2 / AU-12 / AU-11 (365-day retention via
`compliance.audit.retentionDays: 365`).

## Verifying the cluster is ready

The smoke script:
```bash
./scripts/cluster-prereq-check.sh openclaw
```
Exits 0 with a green checklist when ready. (Script lives alongside the
chart; it shells the kubectl checks listed above.)

## Verifying after install

```bash
# 1. All sub-charts deployed.
kubectl -n openclaw get deploy,svc,signaturegate,compliancepolicy

# 2. ExternalSecret synced.
kubectl -n openclaw get externalsecret openclaw-pki-org-seed -o yaml | grep -i Synced

# 3. Sekiban verified each workload's signature.
kubectl -n openclaw get signaturegate -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

# 4. Smoke test the store API.
kubectl -n openclaw port-forward svc/openclaw-store-openclaw-skill-store 8080:8080 &
curl -fsS http://localhost:8080/health
kill %1
```

If any step fails, the [RUNBOOK](./RUNBOOK.md) `Health checks` and
`Investigate a failed re-attestation` sections are the entrypoints.
