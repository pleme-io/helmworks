{{/*
pleme-lib: Karpenter primitives — NodePool + EC2NodeClass

These helpers render Karpenter v1 resources from values-supplied maps, allowing
a single chart to declare multiple pools / classes. Consumers structure values as:

  karpenter:
    nodePools:
      <name>:                 # rendered as NodePool/<name>
        weight: 50
        limits: { cpu: "100", memory: "400Gi" }
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 1m
        template:
          metadata:
            labels: { ... }
          spec:
            taints: [ ... ]
            requirements: [ ... ]
            nodeClassRef:
              group: karpenter.k8s.aws
              kind: EC2NodeClass
              name: general
            expireAfter: 8h
            terminationGracePeriod: 10m
    ec2NodeClasses:
      <name>:                 # rendered as EC2NodeClass/<name>
        role: KarpenterNodeRole-<cluster>
        amiFamily: Bottlerocket
        amiSelectorTerms: [ ... ]
        subnetSelectorTerms: [ ... ]
        securityGroupSelectorTerms: [ ... ]
        blockDeviceMappings: [ ... ]
        metadataOptions: { ... }

Both helpers are no-ops if the corresponding values map is empty / absent.
Sekiban attestation annotations are applied when attestation.enabled is true —
NodePools and EC2NodeClasses gate compute admission, so integrity matters.
*/}}

{{- define "pleme-lib.karpenterNodePool" -}}
{{- range $name, $spec := (.Values.karpenter).nodePools }}
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: {{ $name | kebabcase }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.attestationAnnotations" $) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  {{- if hasKey $spec "weight" }}
  weight: {{ $spec.weight }}
  {{- end }}
  {{- with $spec.limits }}
  limits:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $spec.disruption }}
  disruption:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  template:
    metadata:
      {{- with $spec.template.metadata }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    spec:
      {{- with $spec.template.spec }}
      {{- tpl (toYaml .) $ | nindent 6 }}
      {{- end }}
{{- end }}
{{- end }}


{{- define "pleme-lib.karpenterEC2NodeClass" -}}
{{- range $name, $spec := (.Values.karpenter).ec2NodeClasses }}
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: {{ $name | kebabcase }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.attestationAnnotations" $) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  {{- tpl (toYaml $spec) $ | nindent 2 }}
{{- end }}
{{- end }}
