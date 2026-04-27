# Air-Gap Pattern — pleme-io helmworks

Authoritative pattern for deploying an air-gapped K8s cluster from
helmworks, where every workload's container image comes from a
cluster-local registry and the cluster has zero direct external
image-supply egress.

> Companion: [`COMPLIANCE-PROOF.md`](./COMPLIANCE-PROOF.md) — the
> machine-checked proof that consumer charts using only the
> `pleme-lib.compliance.*` primitives cannot produce a non-compliant
> K8s architecture at the chart layer (FedRAMP-High mappings + air-gap
> §3.5).

---

## 1. The architecture

```
┌─────────────────────────────────── Cluster boundary ───────────────────────────────────┐
│                                                                                        │
│   ┌─────────────────────────────────────────────────────────┐                          │
│   │  Consumer namespace (regulated, observability, …)       │                          │
│   │                                                         │                          │
│   │  ┌─────────────────┐    ┌─────────────────┐             │                          │
│   │  │ pleme-microsvc  │    │ pleme-worker    │   …         │                          │
│   │  │ airgap=consumer │    │ airgap=consumer │             │                          │
│   │  └────────┬────────┘    └────────┬────────┘             │                          │
│   │           │                      │                      │                          │
│   │           │ image pull           │ image pull           │                          │
│   │           │ (egress NetworkPolicy: only zot.registry)   │                          │
│   │           ▼                      ▼                      │                          │
│   └───────────┼──────────────────────┼──────────────────────┘                          │
│               │                      │                                                 │
│   ┌───────────┴──────────────────────┴──────────────────────┐                          │
│   │  Registry namespace                                     │                          │
│   │                                                         │                          │
│   │  ┌─────────────────────────────────────────────────┐    │                          │
│   │  │ pleme-zot (StatefulSet, registry-mirror role)   │    │                          │
│   │  │ • OIDC auth (Authentik)                         │    │                          │
│   │  │ • encrypted PVC (SC-28)                         │    │                          │
│   │  │ • cosign verification at boundary (SI-7)        │    │                          │
│   │  │ • Audit logs to Vector → SIEM                   │    │                          │
│   │  │ • mTLS via Istio PeerAuthentication=STRICT      │    │                          │
│   │  └────────────────────┬────────────────────────────┘    │                          │
│   │                       │                                 │                          │
│   │                       │ image push                      │                          │
│   │                       ▲                                 │                          │
│   │  ┌────────────────────┴────────────────────────────┐    │                          │
│   │  │ pleme-image-sync (CronJob, registry-mirror)     │    │                          │
│   │  │ • skopeo copy with cosign verify                │    │                          │
│   │  │ • upstream creds via Akeyless target → Secret   │    │                          │
│   │  │ • structured JSON logs to AU-2/AU-12 pipeline   │    │                          │
│   │  └────────────────────┬────────────────────────────┘    │                          │
│   │                       │                                 │                          │
│   └───────────────────────┼─────────────────────────────────┘                          │
│                           │                                                            │
│                           │ external egress                                            │
│                           │ (mirrorEgressPolicy NetworkPolicy:                         │
│                           │   only allowedCidrs / FQDN allowlist)                      │
└───────────────────────────┼────────────────────────────────────────────────────────────┘
                            │
                            ▼
                  ┌──────────────────────┐
                  │ Upstream allowlist:  │
                  │  • ghcr.io           │
                  │  • quay.io           │
                  │  • registry.k8s.io   │
                  └──────────────────────┘
```

The trust-boundary egress for the cluster's image-supply path is
**exactly one edge**: pleme-image-sync → upstream allowlist. Every other
workload talks only to Zot.

---

## 2. The compounding-layer recipe

The pattern is built out of generic primitives; air-gap is one consumer.

```
Layer 0:  pleme-lib core compliance (baseline, security, network,
                                     availability, audit, attestation,
                                     RBAC, secrets, storage, ingress)
                                          │
Layer 1:  egress (toService / toUpstream)  ← reusable for "talks-only-to-X"
          authz  (Role / RoleBinding / no-wildcards) ← every chart with RBAC
          authn  (OIDC / mTLS / projected token)     ← every chart with auth
                                          │
Layer 2:  airgap (consumer + registry-mirror roles)  ← composes egress + authz
          mirror (scheduled-sync shape)              ← composes airgap + audit
                                          │
Layer 3:  pleme-zot          ← consumes Layer 2 (registry-mirror)
          pleme-image-sync   ← consumes Layer 2 (mirror + registry-mirror)
```

Future consumers of Layer 2 are mechanical — for example a Helm-chart
mirror would be ~60 lines of values + a simple CronJob that skopeo-copies
OCI artifacts (Helm charts are OCI artifacts) into Zot. All air-gap
guarantees inherited.

---

## 3. Quickstart — three releases

```bash
# 1. Namespace scaffolding (PSS=restricted, default-deny NetworkPolicy,
#    ResourceQuota, LimitRange) for the registry namespace.
helm install registry-ns oci://ghcr.io/pleme-io/charts/pleme-compliance \
  --namespace registry --create-namespace \
  --set compliance.baseline=fedramp-high

# 2. Zot registry.
helm install zot oci://ghcr.io/pleme-io/charts/pleme-zot \
  --namespace registry \
  -f examples/zot-fedramp-high.yaml

# 3. Image-sync mirror.
helm install image-sync oci://ghcr.io/pleme-io/charts/pleme-image-sync \
  --namespace registry \
  -f examples/image-sync-fedramp-high.yaml

# 4. Consumer workloads (in their own namespace).
helm install regulated-ns oci://ghcr.io/pleme-io/charts/pleme-compliance \
  --namespace regulated --create-namespace \
  --set compliance.baseline=fedramp-high

helm install my-service oci://ghcr.io/pleme-io/charts/pleme-microservice \
  --namespace regulated \
  -f examples/fedramp-high-airgap.yaml
```

Every chart in this chain validates at template render — non-compliant
inputs `fail()` the install before any cluster object is created.

---

## 4. Required cluster-side guarantees

The chart-render proof in [`COMPLIANCE-PROOF.md`](./COMPLIANCE-PROOF.md)
covers the bytes that `helm template` produces. For end-to-end air-gap
correctness, the *cluster* must additionally enforce:

| Guarantee | Mechanism in pleme-io |
|-----------|------------------------|
| Pod Security Standard (`restricted`) admission       | K8s built-in PSS controller; `pleme-compliance` namespace chart sets the labels |
| NetworkPolicy actually blocks traffic                | Cilium with `enable-policy=always`; cluster-side `CiliumNetworkPolicy` defaults |
| Sekiban admission verifies attestation annotations   | `sekiban` ValidatingAdmissionWebhook deployed; reachable from kube-apiserver |
| Cosign signatures verified at registry boundary      | Zot `extensions.scrub` + `extensions.sign`; cosign public key in `cosign-pub` Secret rotated by External Secrets Operator |
| Encrypted storage class is *actually* encrypted      | CSI driver with FIPS-validated KMS-backed key (e.g. AWS EBS CSI + KMS, or rook-ceph + dm-crypt) |
| Upstream registry credentials rotated                | Akeyless target → External Secrets Operator → `image-sync-*-creds` Secrets refreshed every 24h |
| kube-state-metrics CronJob audit                     | kube-state-metrics scraping `kube_cronjob_*`; Vector pipeline ships pod logs to Splunk HEC / VictoriaLogs |
| FQDN egress (when `useCilium=true`)                  | Cilium L7 DNS proxy enabled cluster-wide |
| Image bytes match digest                             | Zot stores by digest; OCI distribution spec immutable-tag enforcement |

The cluster repo (`pleme-io/k8s/clusters/<cluster>`) is responsible for
declaring each of these via FluxCD HelmReleases. The proof at the chart
layer is necessary; cluster guarantees make it sufficient.

---

## 5. Modes of operation

### 5.1 Cache mode (default, most secure)

```yaml
mode: cache
compliance.airgap.upstream.allowedCidrs: ["127.0.0.1/32"]    # sentinel, no real egress
```

- Zot has zero direct upstream egress (NetworkPolicy effectively deny-all
  external)
- `pleme-image-sync` is the only workload allowed external egress (its
  own `mirrorEgressPolicy` allows the upstream allowlist)
- Pushes from image-sync into Zot via in-cluster Service traffic
- Maximum operational simplicity for FedRAMP-High and DoD environments

### 5.2 Pull mode

```yaml
mode: pull
compliance.airgap.upstream.allowedCidrs:
  - "140.82.112.0/20"     # GitHub (ghcr.io)
  - "104.16.0.0/13"       # Cloudflare
compliance.airgap.upstream.credentialSecret: zot-sync-creds
upstream.registries:
  - urls: ["https://ghcr.io"]
    pollInterval: "1h"
    credentialsSecret: zot-sync-creds
    content:
      - prefix: "pleme-io/**"
        tags:
          regex: "^v?\\d+\\.\\d+\\.\\d+$"
```

- Zot itself fetches from upstream (via its `extensions.sync`)
- `pleme-image-sync` is unnecessary
- `pleme-zot` becomes the registry-mirror role's *real* egress workload
- Smaller surface but couples registry serving + upstream fetching in one
  workload — slightly weaker separation of concerns than cache mode

---

## 6. Compliance posture summary

A workload deployed via the air-gap pattern at `compliance.baseline=fedramp-high`
satisfies (at the chart layer; cluster guarantees in §4):

- **CM-2** Baseline Configuration — image is digest-pinned, references
  the cluster-local registry, attestation hashes embedded
- **CM-7** Least Functionality — pullPolicy=Always, no host namespaces,
  drop ALL caps, no privilege escalation
- **AC-3 / AC-6 / AC-6(1) / AC-6(7)** Access Enforcement / Least Privilege
  — dedicated SA, no wildcard verbs/resources/apiGroups, no
  cluster-admin or system-group bindings
- **AC-4 / SC-7 / SC-7(11) / SC-7(12)** Boundary Protection — workload
  egresses ONLY to the local registry; default-deny + DNS + TLS-egress
  trio at consumer; upstream-allowlist egress at registry-mirror
- **AC-17 / IA-2 / IA-2(1)** Remote Access / Identification & Auth —
  external Ingress requires OIDC (Authentik forward-auth)
- **IA-3** Device Identification — Istio PeerAuthentication=STRICT for
  service-to-service mTLS at fedramp-high
- **IA-5 / SC-12** Authenticator / Crypto-Key Management — secret-shaped
  env vars must use `secretKeyRef`; upstream registry creds via Secret;
  cosign keys via Secret; SA tokens projected with audience and TTL ≤ 1h
- **AU-2 / AU-3 / AU-11 / AU-12 / SI-4** Audit & Monitoring — mandatory
  ServiceMonitor (or PodMonitor / viaJobEvents); structured JSON logs;
  `audit.pleme.io/*` annotations; image-sync emits per-copy event logs
- **SC-5 / CP-2** DoS Protection / Contingency — `replicaCount >= 2` (or
  `concurrencyPolicy != Allow` for CronJobs); mandatory PDB; topology
  spread (zone + hostname) at fedramp-high
- **SC-8 / SC-13** Transmission Confidentiality — TLS-only egress
  NetworkPolicy on 443; Ingress TLS required at moderate+
- **SC-22** Secure Name Resolution — allow-DNS NetworkPolicy
- **SC-28** Protection of Information at Rest — PVC must use an
  encrypted storage class (default allowlist: `encrypted`,
  `encrypted-fast`, `encrypted-retain`, `fips-encrypted`,
  `csi-encrypted`)
- **SI-7** Software Integrity — image digest pinning; cosign signature
  verification at registry boundary (Zot `extensions.sign`); attestation
  annotations verified by sekiban admission
- **SI-16** Memory Protection — seccompProfile=RuntimeDefault on pod
  and containers

---

## 7. Extending the pattern

Adding a new mirror type — e.g. mirroring Helm charts (OCI artifacts) or
OPA Gatekeeper bundles — looks like:

```yaml
# pleme-helm-mirror/values.yaml
compliance:
  baseline: fedramp-high
  airgap:
    enabled: true
    role: registry-mirror
    requireSignedImages: true
    upstream:
      allowedCidrs: [...]
      credentialSecret: helm-mirror-upstream-creds
  mirror:
    schedule: "0 */4 * * *"
    cosignVerify: true
    cosignKeyRef: { name: cosign-pub, key: cosign.pub }
    upstreams:
      - host: charts.bitnami.com
        credentialSecret: bitnami-creds
        repos: ["bitnami/postgresql", "bitnami/redis"]
```

…and a CronJob template that runs `helm pull --untar` against each
upstream chart and `oras push` into Zot. All air-gap, RBAC, audit,
encryption, attestation guarantees inherited from `pleme-lib`.

That's the compounding payoff: the next mirror is ~60 lines of values
+ ~30 lines of CronJob template, not a thousand lines of compliance
work.
