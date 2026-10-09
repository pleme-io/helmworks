{{/*
pleme-lib.githubAuth — ONE typed GitHub-auth surface for every chart that needs
GitHub credentials. (added v0.53.0)

── THE SHAPE IS NOT OURS ───────────────────────────────────────────────────
`.Values.githubAuth` is the serde shape of shikumi's Rust `GithubAuth`
(snake_case keys, externally tagged), so Nix, Helm and Rust read ONE shape:

  githubAuth:
    token: <SecretSource>                       # a personal/installation token
  # or
    app:                                        # a GitHub App
      app_id: 123                               # integer (Rust u64), required
      owner: pleme-io                           # optional
      installation_id: 456                      # integer, optional (ARC requires it)
      private_key: <SecretSource>               # required
  # or
    chain:                                      # tried IN ORDER by the app
      - token: <SecretSource>
      - app: {...}
  # `gh_cli: {host}` exists in the Rust type but is REFUSED here: it resolves
  # through a `gh` binary and its host login, and a pod has neither.

── THE K8S BINDING: SecretSource as a chart sees it ─────────────────────────
A secret source is a single-key map. Two keys are K8s-only BINDINGS that the
chart resolves; the rest are the shikumi variants, passed through unchanged:

  secretRef:      { name: gh-app, key: private-key.pem, env: VAR? }
                  An existing K8s Secret. Mounted as a file (default) or
                  projected as an env var when `env` is set.
  externalSecret: { key: /remote/path, property: p?, clusterSecretStoreName: s?,
                    refreshInterval: 30m?, env: VAR? }
                  Rendered as an ExternalSecret through pleme-lib.externalSecret
                  (Secret name `<fullname>-github-auth-<slot>`), then bound
                  exactly like a secretRef.
  env:  VAR       passthrough — the pod already carries VAR.
  file: /abs/path passthrough — the pod already carries the file.
  akeyless | vault | aws_secret | gcp_secret
                  passthrough — the app resolves these itself.

REFUSED with a reason: `literal` and a bare string (secret material in values),
`command` / `op` / `sops` (laptop tooling a distroless pod does not ship).

── THE REWRITE (why `.config` exists) ──────────────────────────────────────
`.config` renders the in-pod `github_auth:` block with every binding rewritten
to what the pod actually sees — `{file: <mountPath>/<key>}` or `{env: VAR}` —
so the app's shikumi config reads the SAME shape in a pod as on a laptop. The
rendered block holds only references, never secret material, so it may live in
a ConfigMap (e.g. merged into pleme-lib.tieredConfig's file tier).

Slots: the top-level variant is slot 0; chain entry i is slot i. A file binding
mounts at /var/run/secrets/github-auth/<slot>/<key>, volume `github-auth-<slot>`.

── NAMED TEMPLATES (each takes the root context `.`) ───────────────────────
  pleme-lib.githubAuth.validate        fail()s on every refused shape; emits nothing
  pleme-lib.githubAuth.env             container env: list items (secretKeyRef)
  pleme-lib.githubAuth.volumes         pod volumes: list items (secret volumes)
  pleme-lib.githubAuth.volumeMounts    container volumeMounts: list items
  pleme-lib.githubAuth.config          `github_auth:` YAML block (rewritten)
  pleme-lib.githubAuth.externalSecrets ExternalSecret docs for externalSecret bindings
  pleme-lib.githubAuth.arcSecret       (dict "root" . "name" <secret>) — ARC's
                                       Secret contract; see its own header
  pleme-lib.githubAuth.plan            internal: the validated plan as JSON

All are no-ops when `githubAuth` is absent or empty. Values JSON-schema
fragment: charts/pleme-lib/schemas/github-auth.schema.json.
*/}}

{{- define "pleme-lib.githubAuth.mountRoot" -}}/var/run/secrets/github-auth{{- end -}}

{{/* ── _oneKey: (dict "v" <value> "where" <path> "allowed" <list>) → the one key ── */}}
{{- define "pleme-lib.githubAuth._oneKey" -}}
{{- $v := .v -}}
{{- if not (kindIs "map" $v) -}}
{{- fail (printf "pleme-lib.githubAuth: %s must be a single-key map (one of: %s), got %s" .where (join ", " .allowed) (kindOf $v)) -}}
{{- end -}}
{{- $keys := keys $v | sortAlpha -}}
{{- if ne (len $keys) 1 -}}
{{- fail (printf "pleme-lib.githubAuth: %s must carry exactly one key (one of: %s), got %d: [%s]" .where (join ", " .allowed) (len $keys) (join ", " $keys)) -}}
{{- end -}}
{{- first $keys -}}
{{- end -}}

{{/* ── _fields: (dict "v" <map> "where" <path> "allowed" <list>) — unknown keys fail ── */}}
{{- define "pleme-lib.githubAuth._fields" -}}
{{- range $k := keys .v | sortAlpha -}}
{{- if not (has $k $.allowed) -}}
{{- fail (printf "pleme-lib.githubAuth: %s has unknown key %q (allowed: %s)" $.where $k (join ", " $.allowed)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* ── _envName: (dict "v" <value> "where" <path>) ── */}}
{{- define "pleme-lib.githubAuth._envName" -}}
{{- if not (and (kindIs "string" .v) (regexMatch "^[A-Za-z_][A-Za-z0-9_]*$" .v)) -}}
{{- fail (printf "pleme-lib.githubAuth: %s must be an environment variable name ([A-Za-z_][A-Za-z0-9_]*), got %v" .where .v) -}}
{{- end -}}
{{- end -}}

{{/* ── _uint: (dict "v" <value> "where" <path>) — a positive integer (Rust u64) ── */}}
{{- define "pleme-lib.githubAuth._uint" -}}
{{- $v := .v -}}
{{- $ok := false -}}
{{- if or (kindIs "float64" $v) (kindIs "int" $v) (kindIs "int64" $v) -}}
{{- if and (eq (float64 $v) (float64 (int64 $v))) (gt (float64 $v) 0.0) -}}{{- $ok = true -}}{{- end -}}
{{- end -}}
{{- if not $ok -}}
{{- fail (printf "pleme-lib.githubAuth: %s must be a positive integer (Rust u64), got %s %v" .where (kindOf $v) $v) -}}
{{- end -}}
{{- end -}}

{{/*
── _ref: validate a secretRef / externalSecret binding body.
   (dict "v" <map> "kind" "secretRef"|"externalSecret" "where" <path>)
*/}}
{{- define "pleme-lib.githubAuth._ref" -}}
{{- $v := .v -}}
{{- $where := printf "%s.%s" .where .kind -}}
{{- if not (kindIs "map" $v) -}}
{{- fail (printf "pleme-lib.githubAuth: %s must be a map, got %s" $where (kindOf $v)) -}}
{{- end -}}
{{- if eq .kind "secretRef" -}}
{{- include "pleme-lib.githubAuth._fields" (dict "v" $v "where" $where "allowed" (list "name" "key" "env")) -}}
{{- if not (and (kindIs "string" $v.name) (regexMatch "^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$" ($v.name | default ""))) -}}
{{- fail (printf "pleme-lib.githubAuth: %s.name must be a Secret name (DNS-1123 subdomain), got %v" $where $v.name) -}}
{{- end -}}
{{- if not (and (kindIs "string" $v.key) (regexMatch "^[-._a-zA-Z0-9]+$" ($v.key | default ""))) -}}
{{- fail (printf "pleme-lib.githubAuth: %s.key must be a Secret data key ([-._a-zA-Z0-9]+), got %v" $where $v.key) -}}
{{- end -}}
{{- else -}}
{{- include "pleme-lib.githubAuth._fields" (dict "v" $v "where" $where "allowed" (list "key" "property" "clusterSecretStoreName" "refreshInterval" "env")) -}}
{{- if not (and (kindIs "string" $v.key) $v.key) -}}
{{- fail (printf "pleme-lib.githubAuth: %s.key (the remote secret path) is required" $where) -}}
{{- end -}}
{{- end -}}
{{- if hasKey $v "env" -}}
{{- include "pleme-lib.githubAuth._envName" (dict "v" $v.env "where" (printf "%s.env" $where)) -}}
{{- end -}}
{{- end -}}

{{/*
── _source: one SecretSource → {config, bindings} as JSON.
   (dict "root" . "src" <value> "where" <path> "slot" <int> "role" "token"|"private_key")
*/}}
{{- define "pleme-lib.githubAuth._source" -}}
{{- $src := .src -}}
{{- $where := .where -}}
{{- $passthrough := list "akeyless" "vault" "aws_secret" "gcp_secret" -}}
{{- $allowed := concat (list "secretRef" "externalSecret" "env" "file") $passthrough -}}
{{- if kindIs "string" $src -}}
{{- fail (printf "pleme-lib.githubAuth: %s is a bare string, which shikumi reads as a plaintext literal; a chart never carries secret material in values. Use {secretRef: {name, key}} or {externalSecret: {key}}" $where) -}}
{{- end -}}
{{- if not $src -}}
{{- fail (printf "pleme-lib.githubAuth: %s is required (one of: %s)" $where (join ", " $allowed)) -}}
{{- end -}}
{{- $k := include "pleme-lib.githubAuth._oneKey" (dict "v" $src "where" $where "allowed" $allowed) -}}
{{- $v := get $src $k -}}
{{- $out := dict "config" (dict) "bindings" (list) "envs" (list) -}}
{{- if eq $k "env" -}}
  {{- include "pleme-lib.githubAuth._envName" (dict "v" $v "where" (printf "%s.env" $where)) -}}
  {{- $_ := set $out "config" (dict "env" $v) -}}
  {{- $_ := set $out "envs" (list $v) -}}
{{- else if eq $k "file" -}}
  {{- if not (and (kindIs "string" $v) (hasPrefix "/" $v)) -}}
  {{- fail (printf "pleme-lib.githubAuth: %s.file must be an absolute path, got %v" $where $v) -}}
  {{- end -}}
  {{- $_ := set $out "config" (dict "file" $v) -}}
{{- else if has $k $passthrough -}}
  {{- $_ := set $out "config" $src -}}
{{- else if eq $k "literal" -}}
  {{- fail (printf "pleme-lib.githubAuth: %s.literal puts secret material in chart values; use secretRef or externalSecret" $where) -}}
{{- else if has $k (list "command" "op" "sops") -}}
  {{- fail (printf "pleme-lib.githubAuth: %s.%s resolves through laptop tooling a pod does not ship; use secretRef or externalSecret" $where $k) -}}
{{- else if or (eq $k "secretRef") (eq $k "externalSecret") -}}
  {{- include "pleme-lib.githubAuth._ref" (dict "v" $v "kind" $k "where" $where) -}}
  {{- $b := dict "slot" .slot -}}
  {{- if eq $k "secretRef" -}}
    {{- $_ := set $b "secretName" $v.name -}}
    {{- $_ := set $b "secretKey" $v.key -}}
  {{- else -}}
    {{- $_ := set $b "secretName" (printf "%s-github-auth-%d" (include "pleme-lib.fullname" .root | trunc 48 | trimSuffix "-") (int .slot)) -}}
    {{- $_ := set $b "secretKey" (ternary "token" "private-key.pem" (eq .role "token")) -}}
    {{- $ext := dict "key" $v.key -}}
    {{- range $f := list "property" "clusterSecretStoreName" "refreshInterval" -}}
      {{- if hasKey $v $f -}}{{- $_ := set $ext $f (get $v $f) -}}{{- end -}}
    {{- end -}}
    {{- $_ := set $b "external" $ext -}}
  {{- end -}}
  {{- if hasKey $v "env" -}}
    {{- $_ := set $b "env" $v.env -}}
    {{- $_ := set $out "config" (dict "env" $v.env) -}}
    {{- $_ := set $out "envs" (list $v.env) -}}
  {{- else -}}
    {{- $dir := printf "%s/%d" (include "pleme-lib.githubAuth.mountRoot" .) (int .slot) -}}
    {{- $_ := set $b "mountPath" $dir -}}
    {{- $_ := set $out "config" (dict "file" (printf "%s/%s" $dir $b.secretKey)) -}}
  {{- end -}}
  {{- $_ := set $out "bindings" (list $b) -}}
{{- else -}}
  {{- fail (printf "pleme-lib.githubAuth: %s has unknown secret source %q (allowed: %s)" $where $k (join ", " $allowed)) -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}

{{/*
── _app: validate the non-secret App fields; returns them as JSON (ids as int64).
   (dict "v" <map> "where" <path>)
*/}}
{{- define "pleme-lib.githubAuth._app" -}}
{{- $v := .v -}}
{{- $where := .where -}}
{{- if not (kindIs "map" $v) -}}
{{- fail (printf "pleme-lib.githubAuth: %s must be a map {app_id, owner, installation_id, private_key}, got %s" $where (kindOf $v)) -}}
{{- end -}}
{{- include "pleme-lib.githubAuth._fields" (dict "v" $v "where" $where "allowed" (list "app_id" "owner" "installation_id" "private_key")) -}}
{{- if not (hasKey $v "private_key") -}}
{{- fail (printf "pleme-lib.githubAuth: %s has no private_key; a GitHub App cannot mint a token without one" $where) -}}
{{- end -}}
{{- if not (hasKey $v "app_id") -}}
{{- fail (printf "pleme-lib.githubAuth: %s.app_id is required" $where) -}}
{{- end -}}
{{- include "pleme-lib.githubAuth._uint" (dict "v" $v.app_id "where" (printf "%s.app_id" $where)) -}}
{{- $out := dict "app_id" (int64 $v.app_id) -}}
{{- if hasKey $v "installation_id" -}}
{{- include "pleme-lib.githubAuth._uint" (dict "v" $v.installation_id "where" (printf "%s.installation_id" $where)) -}}
{{- $_ := set $out "installation_id" (int64 $v.installation_id) -}}
{{- end -}}
{{- if hasKey $v "owner" -}}
{{- if not (and (kindIs "string" $v.owner) $v.owner) -}}
{{- fail (printf "pleme-lib.githubAuth: %s.owner must be a non-empty string" $where) -}}
{{- end -}}
{{- $_ := set $out "owner" $v.owner -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}

{{/*
── _entry: one tagged entry (token | app) → {config, bindings} as JSON.
   (dict "root" . "entry" <map> "where" <path> "slot" <int>)
   A `chain` here is a nested one: the top-level chain is unrolled by plan.
*/}}
{{- define "pleme-lib.githubAuth._entry" -}}
{{- $allowed := list "token" "app" "chain" -}}
{{- $k := include "pleme-lib.githubAuth._oneKey" (dict "v" .entry "where" .where "allowed" $allowed) -}}
{{- $v := get .entry $k -}}
{{- if eq $k "gh_cli" -}}
{{- fail (printf "pleme-lib.githubAuth: %s.gh_cli is meaningless in a pod (it resolves through a `gh` binary and its host login, and a pod has neither); use token or app" .where) -}}
{{- else if eq $k "chain" -}}
{{- fail (printf "pleme-lib.githubAuth: %s.chain is nested inside a chain; flatten it into one ordered list" .where) -}}
{{- else if eq $k "token" -}}
{{- $s := include "pleme-lib.githubAuth._source" (dict "root" .root "src" $v "where" (printf "%s.token" .where) "slot" .slot "role" "token") | fromJson -}}
{{- dict "config" (dict "token" $s.config) "bindings" $s.bindings "envs" $s.envs | toJson -}}
{{- else if eq $k "app" -}}
{{- $app := include "pleme-lib.githubAuth._app" (dict "v" $v "where" (printf "%s.app" .where)) | fromJson -}}
{{- $s := include "pleme-lib.githubAuth._source" (dict "root" .root "src" $v.private_key "where" (printf "%s.app.private_key" .where) "slot" .slot "role" "private_key") | fromJson -}}
{{- $_ := set $app "private_key" $s.config -}}
{{- dict "config" (dict "app" $app) "bindings" $s.bindings "envs" $s.envs | toJson -}}
{{- else -}}
{{- fail (printf "pleme-lib.githubAuth: %s has unknown variant %q (allowed: token, app, chain; gh_cli is refused in a pod)" .where $k) -}}
{{- end -}}
{{- end -}}

{{/* ── plan: the validated, rewritten surface as JSON {config, bindings} ── */}}
{{- define "pleme-lib.githubAuth.plan" -}}
{{- $ga := .Values.githubAuth -}}
{{- $plan := dict "config" (dict) "bindings" (list) "envs" (list) -}}
{{- if $ga -}}
  {{- $k := include "pleme-lib.githubAuth._oneKey" (dict "v" $ga "where" "githubAuth" "allowed" (list "token" "app" "chain")) -}}
  {{- if eq $k "chain" -}}
    {{- $chain := $ga.chain -}}
    {{- if not (and (kindIs "slice" $chain) $chain) -}}
    {{- fail "pleme-lib.githubAuth: githubAuth.chain must be a non-empty list of {token: ...} / {app: ...} entries" -}}
    {{- end -}}
    {{- $cfg := list -}}
    {{- $bindings := list -}}
    {{- $envs := list -}}
    {{- range $i, $e := $chain -}}
      {{- $r := include "pleme-lib.githubAuth._entry" (dict "root" $ "entry" $e "where" (printf "githubAuth.chain[%d]" $i) "slot" $i) | fromJson -}}
      {{- $cfg = append $cfg $r.config -}}
      {{- $bindings = concat $bindings $r.bindings -}}
      {{- $envs = concat $envs $r.envs -}}
    {{- end -}}
    {{- $_ := set $plan "config" (dict "chain" $cfg) -}}
    {{- $_ := set $plan "bindings" $bindings -}}
    {{- $_ := set $plan "envs" $envs -}}
  {{- else -}}
    {{- $r := include "pleme-lib.githubAuth._entry" (dict "root" . "entry" $ga "where" "githubAuth" "slot" 0) | fromJson -}}
    {{- $_ := set $plan "config" $r.config -}}
    {{- $_ := set $plan "bindings" $r.bindings -}}
    {{- $_ := set $plan "envs" $r.envs -}}
  {{- end -}}
  {{- /* one env var cannot carry two credentials: a chain that reads the
         same variable twice is a dead entry, and a binding onto a variable
         another entry passes through would shadow it */ -}}
  {{- $seen := dict -}}
  {{- range $e := $plan.envs -}}
    {{- if hasKey $seen $e -}}
    {{- fail (printf "pleme-lib.githubAuth: env %s is named by two sources; each needs its own variable" $e) -}}
    {{- end -}}
    {{- $_ := set $seen $e true -}}
  {{- end -}}
{{- end -}}
{{- $plan | toJson -}}
{{- end -}}

{{- define "pleme-lib.githubAuth.validate" -}}
{{- $_ := include "pleme-lib.githubAuth.plan" . -}}
{{- end -}}

{{- define "pleme-lib.githubAuth.env" -}}
{{- $p := include "pleme-lib.githubAuth.plan" . | fromJson -}}
{{- range $b := $p.bindings }}
{{- if $b.env }}
- name: {{ $b.env }}
  valueFrom:
    secretKeyRef:
      name: {{ $b.secretName }}
      key: {{ $b.secretKey }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "pleme-lib.githubAuth.volumes" -}}
{{- $p := include "pleme-lib.githubAuth.plan" . | fromJson -}}
{{- range $b := $p.bindings }}
{{- if $b.mountPath }}
- name: github-auth-{{ int $b.slot }}
  secret:
    secretName: {{ $b.secretName }}
    items:
      - key: {{ $b.secretKey }}
        path: {{ $b.secretKey }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "pleme-lib.githubAuth.volumeMounts" -}}
{{- $p := include "pleme-lib.githubAuth.plan" . | fromJson -}}
{{- range $b := $p.bindings }}
{{- if $b.mountPath }}
- name: github-auth-{{ int $b.slot }}
  mountPath: {{ $b.mountPath }}
  readOnly: true
{{- end }}
{{- end }}
{{- end -}}

{{- define "pleme-lib.githubAuth.config" -}}
{{- $p := include "pleme-lib.githubAuth.plan" . | fromJson -}}
{{- if $p.config -}}
{{- dict "github_auth" $p.config | toYaml -}}
{{- end -}}
{{- end -}}

{{/*
── externalSecrets: one ExternalSecret per externalSecret binding, rendered by
   pleme-lib.externalSecret (not a second ExternalSecret template). The helper
   reads `.Values.externalSecret`, so it is handed a context whose
   externalSecret.secrets holds ONLY the generated entries — the chart's own
   entries are rendered by the chart's own include, never twice. Store /
   interval / apiVersion defaults are inherited from the chart's block.
*/}}
{{- define "pleme-lib.githubAuth.externalSecrets" -}}
{{- $p := include "pleme-lib.githubAuth.plan" . | fromJson -}}
{{- $secrets := dict -}}
{{- range $b := $p.bindings -}}
{{- with $b.external -}}
{{- $ref := dict "key" .key -}}
{{- with .property }}{{- $_ := set $ref "property" . -}}{{- end -}}
{{- $entry := dict "data" (list (dict "secretKey" $b.secretKey "remoteRef" $ref)) -}}
{{- with .clusterSecretStoreName }}{{- $_ := set $entry "clusterSecretStoreName" . -}}{{- end -}}
{{- with .refreshInterval }}{{- $_ := set $entry "refreshInterval" . -}}{{- end -}}
{{- $_ := set $secrets $b.secretName $entry -}}
{{- end -}}
{{- end -}}
{{- if $secrets -}}
{{- include "pleme-lib.githubAuth._renderExternalSecrets" (dict "root" . "secrets" $secrets) -}}
{{- end -}}
{{- end -}}

{{- define "pleme-lib.githubAuth._renderExternalSecrets" -}}
{{- $root := .root -}}
{{- $es := dict "secrets" .secrets -}}
{{- $base := $root.Values.externalSecret | default dict -}}
{{- range $f := list "clusterSecretStoreName" "refreshInterval" "apiVersion" -}}
{{- if hasKey $base $f -}}{{- $_ := set $es $f (get $base $f) -}}{{- end -}}
{{- end -}}
{{- $vals := omit $root.Values "externalSecret" -}}
{{- $_ := set $vals "externalSecret" $es -}}
{{- $ctx := dict "Values" $vals "Release" $root.Release "Chart" $root.Chart "Capabilities" $root.Capabilities "Template" $root.Template "Files" $root.Files -}}
{{- include "pleme-lib.externalSecret" $ctx -}}
{{- end -}}

{{/*
── arcSecret: project githubAuth onto Actions Runner Controller's Secret
   contract. (dict "root" . "name" <Secret name>)

ARC's listener reads ONE Secret with EXACTLY these keys:
  app   → github_app_id, github_app_installation_id, github_app_private_key
  token → github_token

That Secret is assembled by ESO, because Helm cannot copy bytes out of another
Secret (`lookup` is not hermetic: empty under `helm template` and Flux dry-run).
So the secret half MUST be an `externalSecret` binding; app_id and
installation_id are non-secret and land through the ExternalSecret's
`target.template` with `mergePolicy: Merge`.

Refused, each with a reason: chain (ARC reads exactly one credential and walks
no fallback order), gh_cli, secretRef (bytes Helm cannot copy), env / file /
passthrough backends (the controller reads a Secret, not a pod's environment),
`env` on the externalSecret (no pod to project it into), and an app without
installation_id (ARC requires it).
*/}}
{{- define "pleme-lib.githubAuth.arcSecret" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $ga := $root.Values.githubAuth -}}
{{- if $ga -}}
{{- if not (and (kindIs "string" $name) $name) -}}
{{- fail "pleme-lib.githubAuth.arcSecret: the target Secret name is required" -}}
{{- end -}}
{{- $k := include "pleme-lib.githubAuth._oneKey" (dict "v" $ga "where" "githubAuth" "allowed" (list "token" "app")) -}}
{{- if eq $k "chain" -}}
{{- fail "pleme-lib.githubAuth: ARC reads exactly one credential from one Secret and walks no fallback order; githubAuth.chain cannot project into it — declare a single token or app" -}}
{{- else if eq $k "gh_cli" -}}
{{- fail "pleme-lib.githubAuth: githubAuth.gh_cli is meaningless in a pod (it resolves through a `gh` binary and its host login, and a pod has neither); use token or app" -}}
{{- else if not (has $k (list "token" "app")) -}}
{{- fail (printf "pleme-lib.githubAuth: githubAuth has unknown variant %q (allowed for ARC: token, app)" $k) -}}
{{- end -}}
{{- $v := get $ga $k -}}
{{- $templateData := dict -}}
{{- $src := $v -}}
{{- $where := "githubAuth.token" -}}
{{- $secretKey := "github_token" -}}
{{- if eq $k "app" -}}
  {{- $app := include "pleme-lib.githubAuth._app" (dict "v" $v "where" "githubAuth.app") | fromJson -}}
  {{- if not (hasKey $app "installation_id") -}}
  {{- fail "pleme-lib.githubAuth: githubAuth.app.installation_id is required for ARC (its Secret contract carries github_app_installation_id)" -}}
  {{- end -}}
  {{- $_ := set $templateData "github_app_id" (printf "%d" (int64 $app.app_id)) -}}
  {{- $_ := set $templateData "github_app_installation_id" (printf "%d" (int64 $app.installation_id)) -}}
  {{- $src = $v.private_key -}}
  {{- $where = "githubAuth.app.private_key" -}}
  {{- $secretKey = "github_app_private_key" -}}
{{- end -}}
{{- if kindIs "string" $src -}}
{{- fail (printf "pleme-lib.githubAuth: %s is a bare string, which shikumi reads as a plaintext literal; a chart never carries secret material in values. Use {externalSecret: {key}}" $where) -}}
{{- end -}}
{{- $sk := include "pleme-lib.githubAuth._oneKey" (dict "v" $src "where" $where "allowed" (list "externalSecret")) -}}
{{- if eq $sk "secretRef" -}}
{{- fail (printf "pleme-lib.githubAuth: %s.secretRef cannot project into ARC's Secret — Helm cannot copy bytes out of another Secret; use externalSecret, or keep githubConfigSecret naming a Secret that already holds ARC's keys" $where) -}}
{{- else if ne $sk "externalSecret" -}}
{{- fail (printf "pleme-lib.githubAuth: %s.%s cannot project into ARC's Secret — the controller reads a Secret, not a pod's environment; use externalSecret" $where $sk) -}}
{{- end -}}
{{- $ext := get $src "externalSecret" -}}
{{- include "pleme-lib.githubAuth._ref" (dict "v" $ext "kind" "externalSecret" "where" $where) -}}
{{- if hasKey $ext "env" -}}
{{- fail (printf "pleme-lib.githubAuth: %s.externalSecret.env has no meaning for ARC (there is no pod to project it into); remove it" $where) -}}
{{- end -}}
{{- $ref := dict "key" $ext.key -}}
{{- with $ext.property }}{{- $_ := set $ref "property" . -}}{{- end -}}
{{- $target := dict "name" $name "creationPolicy" "Owner" -}}
{{- if $templateData -}}
{{- $_ := set $target "template" (dict "mergePolicy" "Merge" "data" $templateData) -}}
{{- end -}}
{{- $entry := dict "target" $target "data" (list (dict "secretKey" $secretKey "remoteRef" $ref)) -}}
{{- with $ext.clusterSecretStoreName }}{{- $_ := set $entry "clusterSecretStoreName" . -}}{{- end -}}
{{- with $ext.refreshInterval }}{{- $_ := set $entry "refreshInterval" . -}}{{- end -}}
{{- include "pleme-lib.githubAuth._renderExternalSecrets" (dict "root" $root "secrets" (dict $name $entry)) -}}
{{- end -}}
{{- end -}}
