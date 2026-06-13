# Authentik SSO — the maintained pattern

How to put any app behind the fleet **Authentik** IdP, correct-by-construction.
Distilled from getting rio Grafana working end-to-end, including the **two
non-obvious blockers** that each look correct but silently break SSO. The
pleme-lib primitives below bake both in so you never hit them again.

There are **two modes**. Pick by what the app speaks:

| Mode | When | Primitive |
|---|---|---|
| **Native OIDC** | the app has a real OIDC client (Grafana, Forgejo, Outline, …) | `pleme-lib.authentik*` (this doc) |
| **Forward-auth / proxy** | the app has no auth of its own (Immich, Jellyfin, Paperless, …) | `pleme-lareira._authentik.tpl` (nginx + embedded outpost) |

---

## The two gotchas (why SSO "looks configured" but denies everyone)

Both produce the same misleading Grafana error — **"user not a member of one of
the required groups"** — even when group membership is 100% correct.

### GOTCHA #1 — the groups scope mapping must return a **dict**, not a list

An Authentik scope mapping that returns a bare list is **silently dropped** by
the userinfo endpoint:

```
level=warning logger=authentik.providers.oauth2.views.userinfo
event="Scope returned a non-dict value, ignoring" value=["authentik Admins","saguao"]
```

The claim never reaches the consumer. The expression **must** wrap the value in
a dict keyed by the claim name:

```python
# WRONG — dropped by userinfo:
return [group.name for group in user.ak_groups.all()]
# RIGHT:
return {'groups': [group.name for group in user.ak_groups.all()]}
```

`pleme-lib.authentikGroupsScope` hard-codes the dict form. (Diagnostic:
`kubectl -n authentik logs <server> | grep non-dict`.)

### GOTCHA #2 — the consumer must set `groups_attribute_path`

Even when the claim arrives, Grafana **ignores** it unless told where to look.
Without `groups_attribute_path`, `allowed_groups` matches against an empty set →
denies everyone:

```ini
[auth.generic_oauth]
allowed_groups = saguao
groups_attribute_path = groups   # ← REQUIRED; matches the scope mapping's claim key
```

`pleme-lib.grafanaOidcIni` always sets it.

---

## The identity-model shape that actually applies

Two more things learned the hard way (see `theory`/operator memory):

- **Groups are standalone entries; membership is set USER-SIDE.** A group declared
  with group-side `attrs.users: [!KeyOf ...]` against `state: created` users
  **silently never materialises**. Declare the group standalone (no users list),
  then put `groups: [!Find [authentik_core.group, [name, X]]]` on each user.
- **Users are `state: present`** so membership self-heals every reconcile
  (`state: created` freezes attrs after first apply). The SOPS `!Env` password is
  the deterministic source of truth.

---

## The primitives (pleme-lib ≥ 0.25.0)

IdP side — emit Authentik blueprint `entries:` items (embed with `nindent 6`):

| Template | Emits |
|---|---|
| `pleme-lib.authentikGroupsScope` | the singleton groups ScopeMapping (**dict** — gotcha #1). Emit **once**. |
| `pleme-lib.authentikGroup` | a standalone group (no users list) |
| `pleme-lib.authentikUser` | a user (`state: present` + user-side `!Find` membership) |
| `pleme-lib.authentikOidcApp` | one app: OAuth2Provider + Application + group→app PolicyBinding |

Consumer side:

| Template | Emits |
|---|---|
| `pleme-lib.grafanaOidcIni` | Grafana `[auth.generic_oauth]` map (**`groups_attribute_path`** — gotcha #2) |

### Worked example — add an OIDC app to a blueprint ConfigMap

```yaml
data:
  blueprint.yaml: |
    version: 1
    metadata: { name: my-cluster-sso, labels: { blueprints.goauthentik.io/instantiate: "true" } }
    entries:
{{ include "pleme-lib.authentikGroupsScope" (dict) | nindent 6 }}
{{ include "pleme-lib.authentikGroup" (dict "name" "saguao") | nindent 6 }}
{{ include "pleme-lib.authentikUser" (dict "username" "drzln" "name" "Drzln"
      "email" "drzln@quero.cloud" "passwordEnv" "DRZLN_INITIAL_PASSWORD"
      "groups" (list "authentik Admins" "saguao")) | nindent 6 }}
{{ include "pleme-lib.authentikOidcApp" (dict "ctx" . "app" (dict
      "name" "rio Grafana" "slug" "grafana" "clientId" "grafana-rio"
      "clientSecretEnv" "GRAFANA_OIDC_CLIENT_SECRET"
      "redirectUris" (list (dict "matching_mode" "strict"
        "url" "https://grafana.quero.cloud/login/generic_oauth"))
      "launchUrl" "https://grafana.quero.cloud" "accessGroup" "saguao")) | nindent 6 }}
```

Consumer (Grafana subchart values, `grafana.ini.auth.generic_oauth`):

```yaml
{{ include "pleme-lib.grafanaOidcIni" (dict "sso" .Values.grafanaSso) | nindent 8 }}
```

The `lareira-vm-stack` chart's `global.grafanaSso` already renders the consumer
block with `groups_attribute_path` baked in — set `global.grafanaSso.enabled: true`
+ `allowedGroups: [saguao]` and you're done.

---

## Operational note — blueprints need a trigger to re-apply

Flux updates the blueprint ConfigMap, but Authentik only re-applies on **server
boot** or its ~25-min discovery tick. To apply promptly:

```
kubectl --context <c> -n authentik rollout restart deployment/<release>-server
```

The apply is transactional (all-or-nothing). After a group change, clear stale
sessions/tokens so the next login recomputes claims (or just use a fresh window).

---

## Checklist for a new SSO app

1. Pick the mode (native OIDC → here; no-auth app → forward-auth).
2. Add the access group (`authentikGroup`) + memberships (`authentikUser groups:`).
3. `authentikOidcApp` for the app (provider + application + access binding).
4. `authentikGroupsScope` present **once** in the blueprint.
5. Consumer config via `grafanaOidcIni` (or the generic OIDC env for other apps) —
   **`groups_attribute_path` set**.
6. Seed the client-secret `!Env` in the SOPS blueprint-secrets.
7. Commit; restart the authentik server to apply; verify the group claim reaches
   the app (`kubectl logs` the app + grep the auth result).

Tested by `tests/_fixtures/pleme-lib-bare/authentik_oidc_test.yaml` (both gotchas
asserted). Reference deployment: `k8s/clusters/rio/infrastructure/authentik/` +
`lareira-vm-stack` `global.grafanaSso`.
