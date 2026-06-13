{{/*
pleme-lib: Authentik OIDC SSO family — the reusable, correct-by-construction
integration for putting an app behind the fleet Authentik IdP via native OIDC.

This family encodes the COMPLETE working pattern we proved on rio Grafana,
INCLUDING the two non-obvious blockers that each look correct but silently break
SSO. They are impossible to get wrong when you use these templates:

  GOTCHA #1 (IdP side) — the `groups` scope mapping MUST return a DICT of claims
  ({'groups': [...]}), NOT a bare list. Authentik's userinfo endpoint logs
  "Scope returned a non-dict value, ignoring" and drops a bare list entirely, so
  the consumer never sees groups. `pleme-lib.authentikGroupsScope` hard-codes the
  dict form.

  GOTCHA #2 (consumer side) — the relying party MUST extract groups via an
  explicit path (Grafana: `groups_attribute_path = groups`). Without it the RP
  ignores the groups claim even when present, and group-gated login fails "user
  not a member of one of the required groups". `pleme-lib.grafanaOidcIni` always
  sets it.

The other Authentik SSO mode — forward-auth / proxy for apps that don't speak
OIDC (most lareira-* homelab apps) — lives in `pleme-lareira._authentik.tpl`.
This file is the NATIVE-OIDC mode (Grafana, and any app with a real OIDC client).

── IdP side: blueprint entries ──────────────────────────────────────────────
These emit Authentik blueprint `entries:` list items at 0-indent; a chart embeds
them into its blueprint ConfigMap with `nindent 6` (the entries level). Custom
Authentik YAML tags (!Find / !KeyOf / !Env) are emitted as raw text.

  pleme-lib.authentikGroupsScope         singleton groups ScopeMapping (dict!)   — emit ONCE
  pleme-lib.authentikGroup               standalone group entry (no users list)
  pleme-lib.authentikUser                user entry (state:present + user-side !Find membership)
  pleme-lib.authentikOidcApp             one app: OAuth2Provider + Application + group PolicyBinding

── Consumer side ────────────────────────────────────────────────────────────
  pleme-lib.grafanaOidcIni               Grafana [auth.generic_oauth] map (groups_attribute_path baked in)

Why the group/user shapes are what they are (proven on rio): a group declared
with group-side `attrs.users: [!KeyOf ...]` against state:created users SILENTLY
never materialises. The mechanism that works is a STANDALONE group (no users
list) declared before the users, plus USER-SIDE membership via
`groups: [!Find [authentik_core.group, [name, X]]]`, with users on
`state: present` so membership self-heals every reconcile.
*/}}

{{/* internal: family apiVersion-less helpers operate on plain Authentik blueprint YAML. */}}

{{/* ── GOTCHA #1: the groups scope mapping — ALWAYS returns a dict ──────────
   arg: (dict "scopeName" "groups" "id" "..." "name" "...")  (all optional)
   Emit this ONCE per blueprint. Every OIDC provider that needs group claims
   references it by name via !Find on scope_name. */}}
{{- define "pleme-lib.authentikGroupsScope" -}}
{{- $scope := .scopeName | default "groups" -}}
{{- $id := .id | default "groups-scope" -}}
{{- $name := .name | default "groups" -}}
- model: authentik_providers_oauth2.scopemapping
  id: {{ $id }}
  identifiers:
    name: {{ $name | quote }}
    scope_name: {{ $scope }}
  attrs:
    name: {{ $name | quote }}
    scope_name: {{ $scope }}
    description: "Group membership claim (dict-wrapped so userinfo keeps it)"
    # GOTCHA #1: MUST return a dict — a bare list is dropped by userinfo.
    expression: "return {'{{ $scope }}': [group.name for group in user.ak_groups.all()]}"
{{- end -}}

{{/* ── standalone group (no users list — members set user-side) ───────────
   arg: (dict "name" "saguao" "isSuperuser" false "id" "...")  */}}
{{- define "pleme-lib.authentikGroup" -}}
- model: authentik_core.group
  id: {{ .id | default (printf "%s-group" .name) }}
  identifiers:
    name: {{ .name }}
  attrs:
    is_superuser: {{ .isSuperuser | default false }}
{{- end -}}

{{/* ── user (state:present + user-side !Find membership) ──────────────────
   arg: (dict "username" "x" "name" "X" "email" "x@y" "passwordEnv" "X_PW"
              "groups" (list "quero-users" "saguao") "id" "...")
   state:present so membership self-heals; password is the !Env (SOPS) value. */}}
{{- define "pleme-lib.authentikUser" -}}
- model: authentik_core.user
  id: {{ .id | default (printf "user-%s" .username) }}
  state: present
  identifiers:
    username: {{ .username }}
  attrs:
    name: {{ .name | default .username | quote }}
    {{- with .email }}
    email: {{ . }}
    {{- end }}
    is_active: {{ .isActive | default true }}
    {{- with .passwordEnv }}
    password: !Env {{ . }}
    {{- end }}
    {{- with .groups }}
    groups:
      {{- range . }}
      - !Find [authentik_core.group, [name, {{ . | quote }}]]
      {{- end }}
    {{- end }}
{{- end -}}

{{/* ── one native-OIDC app: provider + application + group access binding ──
   arg: (dict "ctx" $ "app" <appMap>)
   appMap keys:
     name           display name (e.g. "rio Grafana")           [required]
     slug           application slug (e.g. grafana)              [required]
     clientId       OIDC client_id                               [required]
     clientSecretEnv  blueprint !Env name for the client secret [required]
     redirectUris   list of {matching_mode, url}                 [required]
     launchUrl      meta_launch_url                              [required]
     accessGroup    group whose members may launch the app       [required]
     groupsScope    scope_name of the groups mapping (default "groups")
     extraScopes    extra scope_names to attach (default openid,email,profile)
     signingKeyName cert name (default "authentik Self-signed Certificate")
     authzFlow      slug (default default-provider-authorization-implicit-consent)
     invalidationFlow slug (default default-provider-invalidation-flow)
   Emits the OAuth2Provider, the Application, and a PolicyBinding gating the app
   to `accessGroup` (the IdP-side access scope — defense-in-depth + the real gate
   for apps with no RP-side allowed_groups). The provider references the shared
   groups scope mapping emitted by pleme-lib.authentikGroupsScope. */}}
{{- define "pleme-lib.authentikOidcApp" -}}
{{- $a := .app -}}
{{- $groupsScope := $a.groupsScope | default "groups" -}}
{{- $signing := $a.signingKeyName | default "authentik Self-signed Certificate" -}}
{{- $authz := $a.authzFlow | default "default-provider-authorization-implicit-consent" -}}
{{- $inval := $a.invalidationFlow | default "default-provider-invalidation-flow" -}}
- model: authentik_providers_oauth2.oauth2provider
  id: {{ $a.slug }}-oidc
  identifiers:
    name: {{ $a.clientId }}
  attrs:
    name: {{ $a.clientId }}
    authorization_flow: !Find [authentik_flows.flow, [slug, {{ $authz }}]]
    invalidation_flow: !Find [authentik_flows.flow, [slug, {{ $inval }}]]
    client_type: confidential
    client_id: {{ $a.clientId }}
    client_secret: !Env {{ $a.clientSecretEnv }}
    redirect_uris:
      {{- range $a.redirectUris }}
      - matching_mode: {{ .matching_mode | default "strict" }}
        url: {{ .url | quote }}
      {{- end }}
    signing_key: !Find [authentik_crypto.certificatekeypair, [name, {{ $signing | quote }}]]
    property_mappings:
      {{- range ($a.extraScopes | default (list "openid" "email" "profile")) }}
      - !Find [authentik_providers_oauth2.scopemapping, [scope_name, {{ . }}]]
      {{- end }}
      # the shared dict-returning groups scope (GOTCHA #1)
      - !Find [authentik_providers_oauth2.scopemapping, [scope_name, {{ $groupsScope }}]]
- model: authentik_core.application
  id: {{ $a.slug }}-app
  identifiers:
    slug: {{ $a.slug }}
  attrs:
    name: {{ $a.name | quote }}
    provider: !KeyOf {{ $a.slug }}-oidc
    meta_launch_url: {{ $a.launchUrl | quote }}
    policy_engine_mode: any
    group: {{ $a.accessGroup }}
# IdP-side access gate: only members of accessGroup may launch the app.
- model: authentik_policies.PolicyBinding
  id: {{ $a.slug }}-{{ $a.accessGroup }}-binding
  identifiers:
    target: !KeyOf {{ $a.slug }}-app
    group: !Find [authentik_core.group, [name, {{ $a.accessGroup }}]]
    order: 0
  attrs:
    enabled: true
    negate: false
    timeout: 30
{{- end -}}

{{/* ── GOTCHA #2: Grafana [auth.generic_oauth] map (groups_attribute_path baked in) ──
   arg: (dict "sso" <ssoMap>)  — ssoMap mirrors global.grafanaSso:
     clientId, clientSecretEnvSecret, clientSecretEnvKey (or rely on envValueFrom),
     authUrl, tokenUrl, apiUrl, scopes (default "openid email profile groups"),
     allowedGroups (list), roleAttributePath, name (button label), allowSignUp, rootUrl
   Returns the grafana.ini auth.generic_oauth submap — drop it under
   grafana.ini.auth.generic_oauth in the grafana subchart values. groups_attribute_path
   is ALWAYS set to the groups claim key (matches authentikGroupsScope). */}}
{{- define "pleme-lib.grafanaOidcIni" -}}
{{- $s := .sso -}}
enabled: true
name: {{ $s.name | default "Authentik" | quote }}
allow_sign_up: {{ $s.allowSignUp | default true }}
client_id: {{ $s.clientId }}
scopes: {{ $s.scopes | default "openid email profile groups" | quote }}
auth_url: {{ $s.authUrl | quote }}
token_url: {{ $s.tokenUrl | quote }}
api_url: {{ $s.apiUrl | quote }}
# GOTCHA #2: without this Grafana ignores the groups claim → group-gated login
# always fails "not a member of required groups". Matches the claim key emitted
# by pleme-lib.authentikGroupsScope.
groups_attribute_path: {{ $s.groupsAttributePath | default "groups" }}
{{- with $s.allowedGroups }}
allowed_groups: {{ join "," . | quote }}
{{- end }}
{{- with $s.roleAttributePath }}
role_attribute_path: {{ . | quote }}
{{- end }}
{{- end -}}
