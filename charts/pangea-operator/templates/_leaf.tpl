{{- define "pangea-operator.leaf" -}}
{{- $leaf := .Values.leaf | default dict -}}
{{- $nats := $leaf.nats | default dict -}}
{{- $auth := $nats.auth | default dict -}}
{{- $js := $leaf.jetstream | default dict -}}
{{- $workers := $leaf.workers | default dict -}}
{{- $scale := $workers.autoscaling | default dict -}}
{{- $deriv := $workers.derivation | default dict -}}
{{- $queue := $leaf.queue | default "in_process" -}}
{{- $url := $nats.url | default "" -}}
{{- toYaml (dict
  "queue" $queue
  "declared" (eq $queue "jetstream")
  "active" (and (eq $queue "jetstream") (ne $url ""))
  "url" $url
  "authSecret" ($auth.secretName | default "")
  "userKey" ($auth.userKey | default "user")
  "passwordKey" ($auth.passwordKey | default "password")
  "credentials" ($leaf.credentials | default list)
  "declare" (ne (toString $js.declare) "false")
  "stream" ($js.stream | default "PANGEA_LEAF")
  "duplicateWindow" ($js.duplicateWindow | default "10m")
  "ackWait" ($js.ackWait | default "60s")
  "maxDeliver" ($js.maxDeliver | default 5)
  "replicas" ($workers.replicas | default 0)
  "memory" ($workers.memory | default "derived")
  "baseMi" ($deriv.baseMi | default 24)
  "leafPeakMi" ($deriv.leafPeakMi | default 56)
  "concurrency" ($deriv.concurrency | default 4)
  "providers" (hasKey $deriv "providers" | ternary $deriv.providers 1)
  "providerMi" ($deriv.providerMi | default 33)
  "autoscaling" (ne (toString $scale.enabled) "false")
  "min" ($scale.min | default 0)
  "max" ($scale.max | default 4)
  "target" ($scale.target | default 600)
  "horizonSecs" ($scale.horizonSecs | default 300)
  "stabilizationSecs" (hasKey $scale "scaleDownStabilizationSecs" | ternary $scale.scaleDownStabilizationSecs 300)
) -}}
{{- end }}

{{- define "pangea-operator.leafWorkerName" -}}
{{- printf "%s-leaf-worker" (include "pangea-operator.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "pangea-operator.leafAuthEnv" -}}
{{- $l := . -}}
{{- $env := list -}}
{{- if $l.authSecret -}}
{{- $env = append $env (dict "name" "NATS_USER" "valueFrom" (dict "secretKeyRef" (dict "name" $l.authSecret "key" $l.userKey))) -}}
{{- $env = append $env (dict "name" "NATS_PASSWORD" "valueFrom" (dict "secretKeyRef" (dict "name" $l.authSecret "key" $l.passwordKey))) -}}
{{- end -}}
{{- toYaml $env -}}
{{- end }}

{{- define "pangea-operator.leafEnv" -}}
{{- $l := include "pangea-operator.leaf" . | fromYaml -}}
{{- $env := list -}}
{{- if $l.declared -}}
{{- $env = list
  (dict "name" "PANGEA_LEAF_QUEUE" "value" "jetstream")
  (dict "name" "PANGEA_LEAF_NATS_URL" "value" $l.url)
  (dict "name" "PANGEA_WORKERS_AUTOSCALING" "value" (toString $l.autoscaling))
  (dict "name" "PANGEA_WORKERS_MEMORY" "value" (toString $l.memory))
-}}
{{- $env = concat $env (include "pangea-operator.leafAuthEnv" $l | fromYamlArray) -}}
{{- end -}}
{{- toYaml $env -}}
{{- end }}

{{- define "pangea-operator.leafWorkerMemory" -}}
{{- $l := . -}}
{{- if eq $l.memory "derived" -}}
{{- $request := add (int $l.baseMi) (mul (int $l.concurrency) (int $l.leafPeakMi)) (mul (int $l.providers) (int $l.providerMi)) -}}
{{- $limit := div (add (mul $request 3) 1) 2 -}}
{{- toYaml (dict "request" (printf "%dMi" $request) "limit" (printf "%dMi" $limit)) -}}
{{- else -}}
{{- toYaml (dict "request" $l.memory "limit" $l.memory) -}}
{{- end -}}
{{- end }}

{{- define "pangea-operator.leafWorker" -}}
{{- $root := .root -}}
{{- $l := include "pangea-operator.leaf" $root | fromYaml -}}
{{- if $l.active }}
{{- $name := include "pangea-operator.leafWorkerName" $root -}}
{{- $mem := include "pangea-operator.leafWorkerMemory" $l | fromYaml -}}
{{- $v := deepCopy .values -}}
{{- $resources := deepCopy ($v.resources | default dict) -}}
{{- $_ := set $resources "requests" (merge (dict "memory" $mem.request) (omit ($resources.requests | default dict) "memory")) -}}
{{- $_ := set $resources "limits" (merge (dict "memory" $mem.limit) (omit ($resources.limits | default dict) "memory")) -}}
{{- $_ := set $v "resources" $resources -}}
{{- $_ := set $v "fullnameOverride" $name -}}
{{- $_ := set $v "nameOverride" $name -}}
{{- $_ := set $v "serviceAccount" (dict "create" false "name" (include "pleme-lib.serviceAccountName" $root)) -}}
{{- $_ := set $v "autoscaling" (dict "enabled" $l.autoscaling) -}}
{{- $_ := set $v "replicaCount" (int $l.replicas) -}}
{{- $_ := set $v "env" (append $v.env (dict "name" "PANGEA_LEAF_ROLE" "value" "worker")) -}}
{{- $ctx := deepCopy $root -}}
{{- $_ := set $ctx "Values" $v }}
---
{{ include "pleme-lib.deployment" $ctx }}
{{- end }}
{{- end }}
