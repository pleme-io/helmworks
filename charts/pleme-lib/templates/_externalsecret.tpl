{{/*
pleme-lib: External Secrets Operator primitive — ExternalSecret

Renders one or more ExternalSecret resources from a values map. Each entry
pulls from a ClusterSecretStore (default: cluster-secret-store; configurable)
and materializes a K8s Secret in the chart's release namespace. Consumers
structure:

  externalSecret:
    clusterSecretStoreName: cluster-secret-store   # default; override per entry as needed
    refreshInterval: 30m                           # default
    secrets:
      <name>:                  # K8s Secret name (also ExternalSecret name)
        # One of:
        #   dataFrom:           extract / find an entire remote secret
        #   data:               map remote keys → secret keys
        # Plus optional:
        #   target:             override target.template / creationPolicy
        #   refreshInterval:    per-entry override
        #   clusterSecretStoreName: per-entry override
        #   secretStoreKind:    ClusterSecretStore (default) | SecretStore

        # Example (extract whole secret from a backend):
        dataFrom:
          - extract:
              key: /example/secrets/example-secret

        # Example (per-key mapping):
        # data:
        #   - secretKey: api-token
        #     remoteRef:
        #       key: /example/secrets/api/token

A no-op if externalSecret.secrets is empty / absent.
*/}}

{{- define "pleme-lib.externalSecret" -}}
{{- $defaultStore := default "cluster-secret-store" (.Values.externalSecret).clusterSecretStoreName }}
{{- $defaultInterval := default "30m" (.Values.externalSecret).refreshInterval }}
{{- $apiVersion := default "external-secrets.io/v1" (.Values.externalSecret).apiVersion }}
{{- range $name, $spec := (.Values.externalSecret).secrets }}
---
apiVersion: {{ $apiVersion }}
kind: ExternalSecret
metadata:
  name: {{ $name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.attestationAnnotations" $) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  refreshInterval: {{ default $defaultInterval $spec.refreshInterval }}
  secretStoreRef:
    kind: {{ default "ClusterSecretStore" $spec.secretStoreKind }}
    name: {{ default $defaultStore $spec.clusterSecretStoreName }}
  target:
    {{- if $spec.target }}
    {{- toYaml $spec.target | nindent 4 }}
    {{- else }}
    name: {{ $name }}
    creationPolicy: Owner
    {{- end }}
  {{- with $spec.dataFrom }}
  dataFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.data }}
  data:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.secret-ref — a typed secret reference, never a value

One entry names where a secret lives (store, key) and where the pod reads it
(path). It renders an ExternalSecret through pleme-lib.externalSecret above
and a read-only secret volume mounted at the path. There is no field that
holds a value: a literal is refused by name, and an unknown field is refused,
so a typo cannot fall through to a plaintext.

  secretRefs:
    - name: kensa-db                    Secret and ExternalSecret name
      store: cluster-secret-store       the store to read from
      storeKind: ClusterSecretStore     ClusterSecretStore (default) | SecretStore
      key: /pleme/kensa/db              the remote key
      property: password                optional field inside the remote secret
      file: password                    optional file name; default property,
                                        else the key's last segment
      path: /var/run/secrets/kensa-db   absolute mount directory, read-only
      refreshInterval: 1h               optional

  pleme-lib.secret-ref           the ExternalSecrets
  pleme-lib.secret-ref.volumes   pod volumes
  pleme-lib.secret-ref.mounts    container volumeMounts

pleme-lib.deployment appends the volumes and mounts when `secretRefs` is set.
*/}}

{{- define "pleme-lib.secret-ref.entries" -}}
{{- $out := list -}}
{{- $seen := dict -}}
{{- range $i, $r := (.Values.secretRefs | default list) -}}
{{- if not (kindIs "map" $r) -}}
  {{- fail (printf "secretRefs[%d] is not a map; a secret reference is {name, store, key, path}" $i) -}}
{{- end -}}
{{- range $k, $_ := $r -}}
  {{- if has $k (list "value" "data" "stringData" "literal") -}}
    {{- fail (printf "secretRefs[%d].%s holds a literal; a secret reference names a store and a key, never the secret itself" $i $k) -}}
  {{- end -}}
  {{- if not (has $k (list "name" "store" "storeKind" "key" "property" "file" "path" "refreshInterval")) -}}
    {{- fail (printf "secretRefs[%d].%s is not a secret-reference field; it takes name, store, storeKind, key, property, file, path and refreshInterval" $i $k) -}}
  {{- end -}}
{{- end -}}
{{- range $k := list "name" "store" "key" "path" -}}
  {{- if not (get $r $k) -}}
    {{- fail (printf "secretRefs[%d].%s is required" $i $k) -}}
  {{- end -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]{0,44}[a-z0-9])?$" $r.name) -}}
  {{- fail (printf "secretRefs[%d].name %q is not a DNS label of at most 46 characters; it names the Secret and its volume" $i $r.name) -}}
{{- end -}}
{{- if hasKey $seen $r.name -}}
  {{- fail (printf "secretRefs[%d] repeats the name %q" $i $r.name) -}}
{{- end -}}
{{- $_ := set $seen $r.name true -}}
{{- $p := trimSuffix "/" (toString $r.path) -}}
{{- if or (not (hasPrefix "/" $p)) (eq $p "/nix/store") (hasPrefix "/nix/store/" $p) -}}
  {{- fail (printf "secretRefs[%d] (%s) path %q is not a mount point; use an absolute path outside /nix/store" $i $r.name (toString $r.path)) -}}
{{- end -}}
{{- if hasKey $seen (printf "path:%s" $p) -}}
  {{- fail (printf "secretRefs[%d] (%s) mounts %q, which another secret reference already mounts" $i $r.name $p) -}}
{{- end -}}
{{- $_ := set $seen (printf "path:%s" $p) true -}}
{{- $kind := $r.storeKind | default "ClusterSecretStore" -}}
{{- if not (has $kind (list "ClusterSecretStore" "SecretStore")) -}}
  {{- fail (printf "secretRefs[%d].storeKind is %q; set ClusterSecretStore or SecretStore" $i $kind) -}}
{{- end -}}
{{- $file := $r.file | default $r.property | default (last (splitList "/" (trimSuffix "/" $r.key))) -}}
{{- if not (regexMatch "^[-._a-zA-Z0-9]+$" $file) -}}
  {{- fail (printf "secretRefs[%d] (%s) resolves the file name %q, which is not a Secret key; set file" $i $r.name $file) -}}
{{- end -}}
{{- $out = append $out (dict "name" (printf "secret-%s" $r.name) "secret" $r.name "path" $r.path "file" $file "kind" $kind "ref" $r) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}

{{- define "pleme-lib.secret-ref" -}}
{{- $entries := include "pleme-lib.secret-ref.entries" . | fromYamlArray -}}
{{- if $entries -}}
{{- $secrets := dict -}}
{{- range $e := $entries -}}
{{- $remote := dict "key" $e.ref.key -}}
{{- with $e.ref.property -}}{{- $_ := set $remote "property" . -}}{{- end -}}
{{- $spec := dict "clusterSecretStoreName" $e.ref.store "secretStoreKind" $e.kind "data" (list (dict "secretKey" $e.file "remoteRef" $remote)) -}}
{{- with $e.ref.refreshInterval -}}{{- $_ := set $spec "refreshInterval" . -}}{{- end -}}
{{- $_ := set $secrets $e.secret $spec -}}
{{- end -}}
{{- $es := dict "secrets" $secrets -}}
{{- $base := .Values.externalSecret | default dict -}}
{{- range $f := list "refreshInterval" "apiVersion" -}}
{{- if hasKey $base $f -}}{{- $_ := set $es $f (get $base $f) -}}{{- end -}}
{{- end -}}
{{- $vals := omit .Values "externalSecret" -}}
{{- $_ := set $vals "externalSecret" $es -}}
{{- $ctx := dict "Values" $vals "Release" .Release "Chart" .Chart "Capabilities" .Capabilities "Template" .Template "Files" .Files -}}
{{- include "pleme-lib.externalSecret" $ctx -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.secret-ref.volumes" -}}
{{- $out := list -}}
{{- range $e := (include "pleme-lib.secret-ref.entries" . | fromYamlArray) -}}
{{- $out = append $out (dict "name" $e.name "secret" (dict "secretName" $e.secret)) -}}
{{- end -}}
{{- with $out -}}{{- toYaml . -}}{{- end -}}
{{- end }}

{{- define "pleme-lib.secret-ref.mounts" -}}
{{- $out := list -}}
{{- range $e := (include "pleme-lib.secret-ref.entries" . | fromYamlArray) -}}
{{- $out = append $out (dict "name" $e.name "mountPath" $e.path "readOnly" true) -}}
{{- end -}}
{{- with $out -}}{{- toYaml . -}}{{- end -}}
{{- end }}
