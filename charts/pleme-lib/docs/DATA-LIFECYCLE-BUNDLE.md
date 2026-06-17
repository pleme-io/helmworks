# The data-lifecycle bundle — abstracting everything shinka does

> Design doc (2026-06-17). The destination is **one typed `.Values` border** that
> synthesizes a stateful service's entire data plane — the CNPG cluster, the
> per-app database, the shinka migration, the migrate→wait→serve gate, the
> backup, the breathe bands, the cofre secret refs, and the DB observability —
> exactly the way `pleme-lib.observabilityBundle` / `pleme-lib.jetstream` / the
> Vector bundle abstracted *their* domains: **synthesize the WHAT from typed
> values, delegate the HOW to pleme-lib named templates, orthogonal toggles.**
>
> First consumer: **explodey** (the batata-quente PR-review SaaS). explodey is the
> forcing function — its `DEPLOY.md` §3/§4 raw shinka+CNPG wiring collapses to
> this bundle's values + a one-line include.
>
> **Tier-honest** (a `Result::Err` is mitigation, a compile error is
> unrepresentability — and a *named template that doesn't exist yet* is neither):
> this doc states what is LANDED vs the real remaining work, graded against the
> live `pleme-lib` templates + the shinka CRD/binary. The naïve "pure composition,
> owns zero logic" framing is **false** until the delegated helpers exist at the
> claimed surface — most of the work is bringing them up, not the bundle shim.

---

## §0 Naming

The bundle is **`pleme-lib.dataLifecycleBundle`** (descriptive, mirrors
`observabilityBundle` exactly). An earlier draft proposed `gavetaBundle` —
**rejected: `gaveta` is a live rio service** (the private Rust axum+GraphQL app
at drive.quero.cloud), so the name collides. No `pleme-lareira` composition/stack
ships: a `…Stack` that just wraps `{{- if enabled }}{{- include bundle }}` composes
nothing (unlike `vmStack`, which composes N independently-useful VM helpers) —
homelab charts include the bundle directly behind the existing
`pleme-lareira.enabled` master toggle.

---

## §1 What shinka does (the WHAT to package)

`shinka` is a GitOps-native DB-migration operator (Rust/kube-rs), one image
dispatching on `RUN_MODE`:
- **operator** — watches `DatabaseMigration` CRs, runs migration Jobs, serves an
  HTTP API (`/api/v1/.../migrations/{name}`, `/clusters/{c}/ready`) + metrics, does
  leader election. The 6-phase FSM (`Pending → CheckingHealth → WaitingForDatabase
  → Migrating → Ready/Failed`) is "always converges" — five Failed auto-recovery
  strategies, idempotent job completion checked before timeout.
- **wait** (`shinka_wait`, an init container) — polls the operator until the named
  migration is `Ready` (migration mode) or the cluster + all its migrations are
  ready (database mode), then exits 0. The migrate→wait→serve readiness gate.

The CRD (`shinka.pleme.io/v1alpha1 DatabaseMigration`) is the full surface:
`database.cnpgClusterRef{name,database?}`; `migrator` **and** ordered `migrators[]`
(sqlx→seaorm cutover); per-`MigratorSpec` `{name?,type,deploymentRef{name,
containerName?},imageOverride?,command?,args?,workingDir?,migrationsPath?,env?,
toolConfig?,secretRefs?,envFrom?,resources?,serviceAccountName?}` across 11
`MigratorType`s; `safety{requireHealthyCluster,maxRetries,checksumMode,
continueOnFailure}`; `timeouts.migration`; and the two load-bearing annotations
(`shinka.pleme.io/retry`, `release.shinka.pleme.io/expected-tag`).

The shared **operator deployment** itself is never abstracted today and is a HARD
prereq: it is undeployed on rio, **zero `DatabaseMigration` CRs have ever
reconciled** there (gaveta carries `shinkaWait.enabled:false`). It must ship as a
FluxCD HelmRelease (pinned image) under `infrastructure/shinka/` — a shared
component, not per-app.

---

## §2 What shinka pairs with (the bundle boundary)

A migrated stateful service needs, alongside shinka:

| Pairing | Synthesized by | In-scope tier |
|---|---|---|
| CNPG `Cluster` (own) / reference to a shared one | `pleme-lib.cnpgCluster` *(new helper — see §4)* | must-have |
| Per-app role + database | a declared CNPG `Database` CR (PLATFORM-MEDIATED) — **not** an imperative bootstrap Job | must-have |
| The `DatabaseMigration` CR | `pleme-lib.shinkaDatabaseMigration` *(extended — §3)* | **LANDED** |
| The migrate→wait→serve init gate | `pleme-lib.shinkaWaitInitContainer` *(extended — §3)* consumed by `_deployment.tpl` | LANDED (helper) / §4 (wiring) |
| Backup / PITR | `pleme-lib.cnpgScheduledBackup` (own+WAL) / logical pg_dump CronJob (reference) *(new)* | must-have |
| breathe bands on the DB | the **existing** `pleme-lib.breatheBand` external-`targetRef` path (`{apiVersion: postgresql.cnpg.io/v1, kind: Cluster, name}`) — **the bundle does NOT add a breathe axis** | reference existing |
| DB creds | cofre `SecretRef` → SOPS/ESO Secret, referenced (not minted) | reference existing |
| DB observability | the **existing** `observabilityBundle` (CNPG podMonitor) | reference existing |

Deliberately *out* of the must-have bundle (nice-to-have / future, ranked):
seeding/fixtures (post-migrate data load), down-migration/rollback (Urdume L0 is
add-only — never-drop — so rollback = redeploy the prior image, not a down
migration), schema-drift detection, a pgbouncer pooler + its AppBand, read-replica
HA, PITR drill (`pitr-tools` DrillKind), galho/eclusa per-PR isolated DB state
(branch-aware migrations), tameshi attestation of a migration receipt, and the
Viggy "schema is current" promessa. Each is a future axis; none blocks M0.

---

## §3 What is LANDED — `_shinka.tpl` extended to the full CRD + wait surface

`pleme-lib` **0.29.0** ships the extended `_shinka.tpl` (additive — a values shape
that set only the legacy fields renders byte-identically). It is the P1 foundation
the bundle composes:

- **`pleme-lib.shinka.migratorFields`** — a DRY helper rendering the full
  `MigratorSpec` (`imageOverride`/`args`/`workingDir`/`migrationsPath`/`toolConfig`/
  `secretRefs`/`envFrom`/`deploymentRef.containerName`) with a **migrator-type
  allowlist guard** (`fail()` on an unknown type). Powers both the singular
  `migrator:` and the new `migrators[]` path.
- **`migrators[]`** — the ordered multi-migrator list (sqlx→seaorm sequential
  cutover); wins over the singular `migrator` per the CRD.
- **the `database` guard** — `cnpgClusterRef.database` (an `Option`) is now
  `{{- with }}`-gated (was rendered unconditionally → an empty key).
- **annotations passthrough** — the retry + expected-tag signals.
- **`shinkaWaitInitContainer`** — the full `shinka_wait` env surface: `CHECK_MODE`
  (migration|database, verified against `src/bin/shinka_wait.rs`), `CLUSTER_NAME`,
  `DATABASE`, `SHINKA_URL`, `HTTP_REQUEST_TIMEOUT_SECONDS`,
  `HTTP_CLIENT_TIMEOUT_SECONDS`, `securityContext`.

**Coverage greatly increased:** `tests/pleme-microservice/shinka_{migration,wait}_test.yaml`
went from 5 → 17 assertions covering every new field, the `migrators[]` path, the
type-allowlist `failedTemplate`, the database guard (negative), defaults, the
database-mode wait, the SHINKA_URL/timeout env, the absent-by-default negatives,
and the securityContext. `helm unittest pleme-microservice` is green (172 tests).

---

## §4 The real remaining work (the honest P0/P1 burndown)

The bundle is a thin remap shim (the `deepCopy .Values` → `set` → `$ctx` pattern,
identical to `observabilityBundle`) — but it composes helpers that are still
incomplete or absent. **This is the work, not the shim:**

1. **The wait wiring (blocking).** `_deployment.tpl` reads `.Values.shinkaWait`
   directly; a named template cannot mutate values a sibling reads. So the bundle's
   single border is *not* one contract until `_deployment.tpl` reads the resolved
   wait dict (`.Values.dataLifecycle.wait | default .Values.shinkaWait`) with
   back-compat. Land in pleme-lib FIRST; test that `dataLifecycle.wait.enabled`
   alone renders `initContainers[0].name == wait-for-migrations`.
2. **The single-emitter rule (blocking).** When a chart consumes both the bundle
   and `pleme-microservice`'s native `shinka-migration.yaml`, only ONE may emit the
   `DatabaseMigration` (same `metadata.name`). Pick one emitter (remap the bundle's
   migration onto the chart's existing `.Values.shinkaMigration`) + a test asserting
   exactly one `kind: DatabaseMigration` chart-wide.
3. **The CNPG lift (Operating Principle #1 — solve once).** `pleme-lib.cnpgCluster`/
   `cnpgDatabase`/`cnpgScheduledBackup` **do not exist** — they would lift the
   standalone `pleme-cnpg`/`pleme-cnpg-cluster` charts into the library. Do it
   COMPLETELY (port `enableSuperuserAccess`, `postgresql.parameters`, `affinity`,
   the `requireClusterName`/`requireBootstrapMode`/`requireInitdb` guards, the
   bootstrap initdb|recovery + walArchive barman block) and make the standalone
   charts 1-line shims over the new helpers — never two CNPG-Cluster emitters.
4. **The compliance wiring.** `compliance.validate` reads `.Values.persistence`
   (SC-28 storage) + `.Values.env` (IA-5 secrets) — Deployment-shaped paths. The
   bundle's DB storageClass + migrator env live elsewhere, so the SC-28/IA-5 rows
   would **false-green**. Before `validate`, remap the bundle paths onto
   `.Values.persistence`/`.env`; add a test that a non-encrypted DB storageClass at
   fedramp-high actually `fail()`s.
5. **The bundle + catalog.** `pleme-lib.dataLifecycleBundle` composing the above via
   orthogonal toggles + a CATALOG-REFLECTION self-describe entry (a typed list of
   the bundle's axes + a meta-test that fails if an axis lacks a test row) + a
   composition co-render test (bundle + observability + breathe + jetstream:
   no duplicate `metadata.name`, exactly one `DatabaseMigration`, one
   `VMServiceScrape`, wait init ordered first) + a GEN-diff CI harness (net-new;
   helmworks has no pre-merge unittest workflow today).
6. **Leaked defaults.** Any rio/Garage specific (`region: garage`,
   `addressingStyle: path`) must NOT be a generic default — AWS-standard or no
   default; rio specifics live in explodey's values.

---

## §5 explodey leverage (the payoff)

Once §4 lands, `DEPLOY.md` §3/§4's raw shinka+CNPG wiring collapses to one
`.Values.dataLifecycle` block + one `{{- include "pleme-lib.dataLifecycleBundle" . }}`:
the per-app CNPG `Database` CR (resolving DEPLOY open-decision #1 the
PLATFORM-MEDIATED way — no bootstrap-Job waiver), the migration (`migrators: [sqlx,
seaorm]`), the wait gate, the WAL/backup, the DB band (via the existing breatheBand
external-targetRef), the cofre cred ref, and the DB observability — one typed
border, every Urdume service the same shape.

**Tier-honest M0 caveat:** explodey M0 consumes the CURRENT shipped subset (the
extended `_shinka.tpl` + the existing CNPG chart by reference); the full bundle
(§4 items 1–6) is the destination explodey drives as the first consumer.
