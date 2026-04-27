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
{{- range $name, $spec := (.Values.externalSecret).secrets }}
---
apiVersion: external-secrets.io/v1beta1
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
    kind: ClusterSecretStore
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
