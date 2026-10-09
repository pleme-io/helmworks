# pleme-lib.githubAuth: one typed GitHub-auth surface

Added in pleme-lib 0.53.0 (2026-10-09). Template: `templates/_github_auth.tpl`.
Schema fragment: `schemas/github-auth.schema.json`. Tests:
`tests/_fixtures/pleme-lib-bare/github_auth_test.yaml` (33 cases) plus the ARC
suites under `tests/pleme-arc-runner-pool/` and `tests/pleme-arc-controller/`.

## The shape belongs to shikumi

`.Values.githubAuth` uses the serde shape of shikumi's Rust `GithubAuth`:
snake_case keys, externally tagged. Nix, Helm and Rust therefore read the same
value. The chart adds no keys of its own to it.

```yaml
githubAuth:
  token: <SecretSource>                 # a token
# or
  app:
    app_id: 123                         # integer, required
    owner: pleme-io                     # optional
    installation_id: 456                # integer, optional (ARC requires it)
    private_key: <SecretSource>         # required
# or
  chain:                                # the app tries these in order
    - token: <SecretSource>
    - app: { ... }
```

The Rust type also has `gh_cli: {host}`. A chart refuses it, because it works
through a `gh` binary and its host login, and a pod has neither.

## SecretSource in a chart

A secret source is a map with exactly one key.

| Key | Meaning | What the pod sees (`.config` output) |
|---|---|---|
| `secretRef: {name, key}` | an existing K8s Secret, mounted as a file | `{file: /var/run/secrets/github-auth/<slot>/<key>}` |
| `secretRef: {name, key, env: VAR}` | the same Secret, set as an env var | `{env: VAR}` |
| `externalSecret: {key, property?, clusterSecretStoreName?, refreshInterval?, env?}` | an ExternalSecret rendered through `pleme-lib.externalSecret` into Secret `<fullname>-github-auth-<slot>` (key `token` or `private-key.pem`), then bound like a secretRef | as for secretRef |
| `env: VAR` / `file: /abs/path` | the pod already has it | unchanged |
| `akeyless` / `vault` / `aws_secret` / `gcp_secret` | the app resolves it itself | unchanged |

Refused, each with its own message:

- `literal` or a bare string: secret material in values.
- `command` / `op` / `sops`: laptop tooling that a pod does not have.

The top-level variant is slot 0, and chain entry `i` is slot `i`. A file
binding mounts as volume `github-auth-<slot>`.

## Named templates

Each one takes the root context `.`. Each is a no-op when `githubAuth` is
absent or empty.

| Template | Emits |
|---|---|
| `pleme-lib.githubAuth.validate` | nothing; `fail`s on every refused shape |
| `pleme-lib.githubAuth.env` | container `env:` list items (`secretKeyRef`) |
| `pleme-lib.githubAuth.volumes` | pod `volumes:` list items (secret volumes) |
| `pleme-lib.githubAuth.volumeMounts` | container `volumeMounts:` list items |
| `pleme-lib.githubAuth.config` | a `github_auth:` YAML block, rewritten to what the pod sees |
| `pleme-lib.githubAuth.externalSecrets` | one ExternalSecret per `externalSecret` binding |
| `pleme-lib.githubAuth.arcSecret` | `(dict "root" . "name" <Secret>)`: ARC's Secret contract, see below |

This is how a consumer wires them. The fragments start with a newline, so
`trim` before `nindent`:

```yaml
env:
  {{- include "pleme-lib.githubAuth.env" . | trim | nindent 2 }}
volumeMounts:
  {{- include "pleme-lib.githubAuth.volumeMounts" . | trim | nindent 2 }}
...
volumes:
  {{- include "pleme-lib.githubAuth.volumes" . | trim | nindent 2 }}
---
{{ include "pleme-lib.githubAuth.externalSecrets" . }}
```

The `.config` block holds references only, never secret material. It can
therefore go in the app's config ConfigMap, so the app's shikumi loader reads
the same `github_auth:` shape in a pod as it does on a laptop.

## Refusals

All of these `fail` at render time, with the path in the message:

- `gh_cli`, at the top level or inside a chain
- two keys in one tagged entry, chain entry or secret source
- an `app` without `private_key` or `app_id`
- a non-integer `app_id` or `installation_id`
- an unknown key at any level
- a nested or empty `chain`
- one env var named by two sources
- a relative `file`

## ARC projection (`arcSecret`)

The Actions Runner Controller reads one Secret with exactly these keys:

- `app` gives `github_app_id`, `github_app_installation_id` and `github_app_private_key`.
- `token` gives `github_token`.

Helm cannot copy bytes out of another Secret: `lookup` returns empty under
`helm template` and under a Flux dry-run. ESO therefore assembles the Secret,
and the secret half must be an `externalSecret` binding. `app_id` and
`installation_id` are not secret. They go in through
`target.template.data` with `mergePolicy: Merge`.

Refused for ARC:

- `chain`: ARC reads exactly one credential.
- `gh_cli`
- `secretRef`
- `env`, `file` and the passthrough backends
- `externalSecret.env`
- an app without `installation_id`

The consumers are:

- **pleme-arc-runner-pool ≥ 0.3.0** materializes the Secret named by
  `gha-runner-scale-set.githubConfigSecret`, the one the upstream scale set
  reads. Leaving `githubAuth` unset keeps the old out-of-band Secret path,
  with a byte-identical render apart from the chart label. Combining
  `githubAuth` with the upstream inline-credentials map form fails.
- **pleme-arc-controller ≥ 0.2.0** materializes the Secret named by
  `githubConfigSecret`. Declaring the same Secret under
  `externalSecret.secrets` as well fails.

## Using the values-schema fragment

Helm cannot `$ref` into a library chart. A packaged dependency is a tarball,
and a library chart's own `values.schema.json` validates only `.Values.pleme-lib`.
To validate at install time, copy the `definitions` from
`schemas/github-auth.schema.json` into your chart's `values.schema.json` and
point `properties.githubAuth` at `#/definitions/GithubAuth`. The render-time
validator above is the gate every consumer gets with no copying. The schema
is the earlier, optional check.

No gate keeps a copied fragment in step with the canonical file:
`pending-schema-lockstep:`.
