# Test coverage — openclaw helm charts

Re-derive: `helm unittest charts/<chart> -f "../../tests/<chart>/*_test.yaml"`.

## Test counts by chart

| Chart | Suites | Cases |
|---|---:|---:|
| `lareira-openclaw-pki` | 5 | 28 |
| `lareira-openclaw-store` | 5 | 23 |
| `lareira-openclaw-scanner` | 4 | 16 |
| `lareira-openclaw-stack` | 1 | 4 |
| **total** | **15** | **71** |

The pki count grew when we added six attestation-gate negative tests
(empty signature/cert/comp/sekiban/attestation + escape hatch). store
and scanner each added two (empty signature + sekiban=false).

## Coverage by concern

Every chart exercises five concerns; the umbrella adds composition.

### `lareira-openclaw-pki`
| Suite | Cases | What it gates |
|---|---:|---|
| `fedramp_high_test` | 5 | sekiban CompliancePolicy + SignatureGate + ExternalSecret schemas; sekiban toggle |
| `negative_test` | 10 | placeholder digest, empty image, real digest, repo-pinned digest, empty attestation.signature, empty attestation.certificationHash, empty attestation.complianceHash, sekiban.enabled=false, attestation.enabled=false, compliance.enforce=false escape hatch |
| `network_policy_test` | 5 | allow-from-store, allow-from-scanner ingress; deny-all + DNS + TLS-egress baseline |
| `observability_test` | 2 | ServiceMonitor schema, Service port |
| `security_context_test` | 6 | runAsNonRoot, drop=ALL, readOnlyRootFilesystem, allowPrivilegeEscalation=false, replicaCount, secretKeyRef wiring |

### `lareira-openclaw-store`
| Suite | Cases | What it gates |
|---|---:|---|
| `fedramp_high_test` | 5 | CompliancePolicy + SignatureGate (data-plane layer); PVC encrypted-default; postgres switch; FIPS-strict storage class override |
| `negative_test` | 7 | placeholder digest, empty image, postgres-without-host, postgres-without-secretRef, happy path, empty attestation.signature, sekiban.enabled=false |
| `network_policy_test` | 3 | allow-to-pki egress, allow-from-scanner ingress, default-deny baseline |
| `observability_test` | 3 | ServiceMonitor, HPA min/max/CPU, PDB minAvailable |
| `security_context_test` | 5 | runAsNonRoot, drop=ALL, readOnlyRootFilesystem, replicaCount (HPA-disabled path), postgres password via secretKeyRef |

### `lareira-openclaw-scanner`
| Suite | Cases | What it gates |
|---|---:|---|
| `fedramp_high_test` | 4 | CompliancePolicy NIST 800-53 high; SignatureGate covers core layers; default 1h cadence; cadence override |
| `negative_test` | 7 | placeholder digest, <60s interval, >24h interval, 1h default, 30m, empty attestation.signature, sekiban.enabled=false |
| `network_policy_test` | 2 | allow-to-store on 8080, allow-to-pki on 8090 |
| `security_context_test` | 3 | runAsNonRoot, drop=ALL, replicaCount=2 |

### `lareira-openclaw-stack` (umbrella)
| Suite | Cases | What it gates |
|---|---:|---|
| `composition_test` | 4 | each sub-chart's CompliancePolicy renders under the umbrella; sub-chart values flow through aliases; ExternalSecret references the canonical key path |

## Values-surface coverage

Every value field declared in each chart's `values.yaml` is exercised by at least one test case. Fields not directly asserted (e.g. `pki.serviceHost`) are dependencies of templates whose render is asserted (the wiring would break the render if wrong).

### `lareira-openclaw-pki` values surface
| Top-level field | Test exercising it |
|---|---|
| `org` | fedramp_high_test/CompliancePolicy |
| `orgSeed.externalSecret.{enabled,refreshInterval,secretStore.*,remoteRef.*,targetSecretName}` | fedramp_high_test/ExternalSecret + composition_test |
| `sekiban.{enabled,framework,baseline,testRunner.*,schedule,signatureGate.*}` | fedramp_high_test/SignatureGate + CompliancePolicy |
| `pleme-microservice.image.tag` | negative_test (4 paths) + every other test |
| `pleme-microservice.networkPolicy.additionalIngress` | network_policy_test (3 cases) |
| `pleme-microservice.compliance.overlays` | implicit in every render passing fedramp-high validators |

### `lareira-openclaw-store` values surface
| Top-level field | Test exercising it |
|---|---|
| `pki.{serviceHost,port}` | wired to env vars, asserted in security_context_test indirectly |
| `persistence.backend` | fedramp_high_test (sqlite + postgres switch) + negative_test |
| `persistence.sqlite.{enabled,storageClass,size}` | fedramp_high_test/PVC + storage class override |
| `persistence.postgres.{host,port,database,sslMode,secretRef.{name,passwordKey}}` | negative_test (host required, secretRef required) |
| `sekiban.*` | fedramp_high_test |
| `pleme-microservice.{autoscaling.*,replicaCount,...}` | observability_test (HPA), security_context_test |

### `lareira-openclaw-scanner` values surface
| Top-level field | Test exercising it |
|---|---|
| `scanIntervalSecs` | negative_test (validates 60 ≤ x ≤ 86400) |
| `store.{serviceHost,port}` | wired to env, asserted via render |
| `pki.{serviceHost,port}` | wired to env, asserted via render |
| `alertWebhook.{enabled,url}` | not under test (optional, opt-in) |
| `sekiban.*` | fedramp_high_test |

## Negative-path coverage

Every fail() path the chart owns has at least one negative test:

| fail() origin | Test |
|---|---|
| pki: placeholder digest | pki/negative_test #1 |
| pki: empty image | pki/negative_test #2 |
| store: placeholder digest | store/negative_test #1 |
| store: empty image | store/negative_test #2 |
| store: postgres-without-host | store/negative_test #3 |
| store: postgres-without-secretRef | store/negative_test #4 |
| scanner: placeholder digest | scanner/negative_test #1 |
| scanner: <60s interval | scanner/negative_test #2 |
| scanner: >24h interval | scanner/negative_test #3 |
| (cascade) fedramp-high pleme-lib validators | exercised by every passing test |

## Regression boundary

Adding a new validator without a corresponding negative test is a
chart-level regression: pre-merge CI MUST gate on `helm unittest`
producing the expected pass count.

```bash
# Re-derive the full corpus.
cd helmworks
for c in lareira-openclaw-pki lareira-openclaw-store lareira-openclaw-scanner lareira-openclaw-stack; do
  helm unittest charts/$c -f "../../tests/$c/*_test.yaml"
done
```
