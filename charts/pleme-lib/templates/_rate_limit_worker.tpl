{{/*
pleme-lib.rate-limit-worker — render a complete rate-limited
consumer worker (Deployment + ConfigMap + Service + ServiceMonitor +
NetworkPolicy + PrometheusRule alerts) from a stable values surface.

Pattern: see pleme-io/theory/RATE-LIMITED-CONSUMERS.md §IV-L1.
Implementation depends on: pleme-io/samba (Rust crate exposing the
UpstreamApi trait + LeakyBucket + JetStreamPullWorker).

────────────────────────────────────────────────────────────────────
WHAT THIS REPLACES
────────────────────────────────────────────────────────────────────

Without this template, every consumer chart re-implements:
  • a Deployment with the strict-singleton Recreate strategy
  • a ConfigMap rendering YAML config from values
  • a Service exposing metrics + health
  • a ServiceMonitor scraping :9090/metrics at 30s
  • a NetworkPolicy allowing DNS + scrape + upstream HTTPS + NATS
  • a PrometheusRule with the four standard alerts (Down, FailureRate,
    Pressure, QueueGrowing)

With this template, those become one-line includes per template file.
The chart's only job is to set `.Values.queueWorker` correctly.

────────────────────────────────────────────────────────────────────
USAGE
────────────────────────────────────────────────────────────────────

In your chart's `values.yaml`:

  queueWorker:
    enabled: true
    image:
      repository: ghcr.io/pleme-io/<binary>
      tag: <pinned-sha>
      pullPolicy: IfNotPresent
    subcommand: throttle           # binary's subcommand for worker mode
    healthPort: 8080

    upstream:
      kind: github                 # github | datadog | slack | …
      budgetPerHour: 5000
      budgetPctMax: 10             # the headline 10% knob

    rateLimit:
      requestsPerMinute: 8         # ★ load-bearing knob
      pressureWarnPct: 50
      pressureCriticalPct: 25
      jitterPct: 0.30
      burst: 1
      honorEtag: true

    nats:
      serverUrl: "nats://pleme-nats.nats.svc:4222"
      stream: "<STREAM_NAME>"
      consumer: "<consumer-name>"
      resultSubject: "<prefix>.results"
      failedSubject: "<prefix>.failed"
      fetchTimeout: "5s"

    auth:
      existingSecret: "<credential-secret>"
      secretKey: "token"
      envName: "UPSTREAM_TOKEN"

    networkPolicy:
      natsNamespace: nats
      allowUpstreamHttps: true     # 443 egress to 0.0.0.0/0 minus RFC1918

In your chart's `templates/`:

  templates/deployment.yaml:    {{- include "pleme-lib.rate-limit-worker.deployment" . }}
  templates/configmap.yaml:     {{- include "pleme-lib.rate-limit-worker.config" . }}
  templates/service.yaml:       {{- include "pleme-lib.rate-limit-worker.service" . }}
  templates/servicemonitor.yaml:{{- include "pleme-lib.rate-limit-worker.servicemonitor" . }}
  templates/networkpolicy.yaml: {{- include "pleme-lib.rate-limit-worker.networkpolicy" . }}
  templates/alerts.yaml:        {{- include "pleme-lib.rate-limit-worker.alerts" . }}

That's the entire chart. New consumers add a values.yaml + a Chart.yaml
that depends on pleme-lib + a directory of one-line template files.
*/}}

{{/* ── Worker config ConfigMap ──────────────────────────────────── */}}
{{- define "pleme-lib.rate-limit-worker.config" -}}
{{- if (.Values.queueWorker).enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "pleme-lib.fullname" . }}-config
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
data:
  config.yaml: |
    upstream:
      kind: {{ .Values.queueWorker.upstream.kind | quote }}
      budget_per_hour: {{ .Values.queueWorker.upstream.budgetPerHour }}
      budget_pct_max: {{ .Values.queueWorker.upstream.budgetPctMax }}

    rate_limit:
      requests_per_minute: {{ .Values.queueWorker.rateLimit.requestsPerMinute }}
      pressure_warn_pct: {{ .Values.queueWorker.rateLimit.pressureWarnPct }}
      pressure_critical_pct: {{ .Values.queueWorker.rateLimit.pressureCriticalPct }}
      jitter_pct: {{ .Values.queueWorker.rateLimit.jitterPct }}
      burst: {{ default 1 .Values.queueWorker.rateLimit.burst }}
      honor_etag: {{ default true .Values.queueWorker.rateLimit.honorEtag }}

    nats:
      server_url: {{ .Values.queueWorker.nats.serverUrl | quote }}
      stream: {{ .Values.queueWorker.nats.stream | quote }}
      consumer: {{ .Values.queueWorker.nats.consumer | quote }}
      result_subject: {{ .Values.queueWorker.nats.resultSubject | quote }}
      failed_subject: {{ .Values.queueWorker.nats.failedSubject | quote }}
      fetch_timeout: {{ .Values.queueWorker.nats.fetchTimeout | quote }}

    metrics:
      port: {{ default 9090 ((.Values.queueWorker).service).metricsPort }}
    health:
      port: {{ default 8080 .Values.queueWorker.healthPort }}
{{- end }}
{{- end }}

{{/* ── Worker Deployment ────────────────────────────────────────── */}}
{{- define "pleme-lib.rate-limit-worker.deployment" -}}
{{- if (.Values.queueWorker).enabled }}
{{- $metricsPort := default 9090 ((.Values.queueWorker).service).metricsPort }}
{{- $healthPort := default 8080 .Values.queueWorker.healthPort }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  # Strict singleton — the rate-limit invariant requires exactly one
  # worker per upstream credential. The pleme-lib template hardcodes
  # this; values.yaml replicaCount is intentionally not surfaced.
  replicas: 1
  strategy:
    # Recreate so two workers never race on the same NATS consumer
    # mid-rollout. The queue tolerates a few-second pause; the
    # invariant is more important than zero-downtime dispatch.
    type: Recreate
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "pleme-lib.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ include "pleme-lib.rate-limit-worker.config" . | sha256sum }}
    spec:
      serviceAccountName: {{ include "pleme-lib.serviceAccountName" . }}
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ default 30 .Values.terminationGracePeriodSeconds }}
      containers:
        - name: worker
          image: "{{ .Values.queueWorker.image.repository }}:{{ .Values.queueWorker.image.tag }}"
          imagePullPolicy: {{ default "IfNotPresent" .Values.queueWorker.image.pullPolicy }}
          args:
            - {{ .Values.queueWorker.subcommand | quote }}
            - "--config"
            - "/etc/pleme-worker/config.yaml"
          env:
            - name: RUST_LOG
              value: {{ default "info" .Values.queueWorker.logLevel | quote }}
            {{- if (.Values.queueWorker).auth }}
            {{- if .Values.queueWorker.auth.existingSecret }}
            - name: {{ default "UPSTREAM_TOKEN" .Values.queueWorker.auth.envName }}
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.queueWorker.auth.existingSecret }}
                  key: {{ default "token" .Values.queueWorker.auth.secretKey }}
            {{- end }}
            {{- end }}
          ports:
            - name: metrics
              containerPort: {{ $metricsPort }}
              protocol: TCP
            - name: health
              containerPort: {{ $healthPort }}
              protocol: TCP
          {{- with .Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            {{- toYaml (default (dict "requests" (dict "cpu" "50m" "memory" "64Mi") "limits" (dict "cpu" "200m" "memory" "256Mi")) .Values.resources) | nindent 12 }}
          livenessProbe:
            httpGet:
              path: /healthz
              port: health
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: health
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 2
          volumeMounts:
            - name: config
              mountPath: /etc/pleme-worker
              readOnly: true
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: config
          configMap:
            name: {{ include "pleme-lib.fullname" . }}-config
        - name: tmp
          emptyDir:
            sizeLimit: 100Mi
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}

{{/* ── Worker Service ───────────────────────────────────────────── */}}
{{- define "pleme-lib.rate-limit-worker.service" -}}
{{- if (.Values.queueWorker).enabled }}
{{- $metricsPort := default 9090 ((.Values.queueWorker).service).metricsPort }}
{{- $healthPort := default 8080 .Values.queueWorker.healthPort }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "pleme-lib.selectorLabels" . | nindent 4 }}
  ports:
    - name: metrics
      port: {{ $metricsPort }}
      targetPort: metrics
      protocol: TCP
    - name: health
      port: {{ $healthPort }}
      targetPort: health
      protocol: TCP
{{- end }}
{{- end }}

{{/* ── Worker ServiceMonitor ────────────────────────────────────── */}}
{{- define "pleme-lib.rate-limit-worker.servicemonitor" -}}
{{- if (.Values.queueWorker).enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: metrics
      path: /metrics
      interval: {{ default "30s" (((.Values.queueWorker).serviceMonitor)).interval }}
      scrapeTimeout: {{ default "10s" (((.Values.queueWorker).serviceMonitor)).scrapeTimeout }}
{{- end }}
{{- end }}

{{/* ── Worker NetworkPolicy ─────────────────────────────────────── */}}
{{- define "pleme-lib.rate-limit-worker.networkpolicy" -}}
{{- if (.Values.queueWorker).enabled }}
{{- $natsNs := default "nats" ((.Values.queueWorker).networkPolicy).natsNamespace }}
{{- $allowUpstream := default true ((.Values.queueWorker).networkPolicy).allowUpstreamHttps }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-deny-all
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-dns
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-scrape
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        {{- range default (list "monitoring") (((.Values.queueWorker).networkPolicy)).prometheusNamespaces }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ . }}
        {{- end }}
      ports:
        - port: metrics
          protocol: TCP
{{- if $allowUpstream }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-upstream
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    # Egress on 443 to all non-private destinations. Tighten with a
    # Cilium L7/FQDN policy where available.
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - port: 443
          protocol: TCP
{{- end }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-nats
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ $natsNs }}
      ports:
        - port: 4222
          protocol: TCP
{{- end }}
{{- end }}

{{/* ── Worker alerts (the standard four) ────────────────────────── */}}
{{/*
The compounding move: every rate-limited consumer in the fleet
emits IDENTICAL alert rules with consumer-specific labels. One
PrometheusRule template, N consumers; new consumer = no new alerts
to write, no spelling drift, no threshold drift.

Metrics emitted by `samba`-based workers (standardized by the trait):
  samba_requests_total{outcome,upstream}    counter
  samba_pace_factor{upstream}               gauge (0..1, current rate multiplier)
  samba_rate_limit_remaining{upstream}      gauge (last seen X-RateLimit-Remaining)
  samba_queue_depth{stream,consumer}        gauge (NATS pending, scraped via exporter)
  samba_dispatch_latency_seconds{upstream}  histogram
*/}}
{{- define "pleme-lib.rate-limit-worker.alerts" -}}
{{- if (.Values.queueWorker).enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $upstream := .Values.queueWorker.upstream.kind }}
{{- $stream := .Values.queueWorker.nats.stream }}
{{- $consumer := .Values.queueWorker.nats.consumer }}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ $fullname }}-rate-limit
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    prometheus: main
    pleme.io/rate-limit-pattern: "true"
spec:
  groups:
    - name: {{ $fullname }}.availability
      interval: 30s
      rules:
        - alert: {{ $fullname | title | replace "-" "" }}Down
          expr: |
            up{job=~".*{{ $fullname }}.*"} == 0
          for: 5m
          labels:
            severity: critical
            component: {{ $fullname }}
            upstream: {{ $upstream | quote }}
          annotations:
            summary: {{ $fullname }} (rate-limited consumer for {{ $upstream }}) down
            description: |
              vmagent has been unable to scrape {{ $fullname }} for 5m.
              Jobs are accumulating in stream {{ $stream }} but not
              being dispatched to {{ $upstream }}.
                kubectl get pod -n {{ "{{" }} $labels.namespace {{ "}}" }} -l app.kubernetes.io/name={{ include "pleme-lib.name" . }}
            runbook_url: https://runbooks.pleme.io/rate-limit/{{ $upstream }}-down

    - name: {{ $fullname }}.dispatch
      interval: 30s
      rules:
        - alert: {{ $fullname | title | replace "-" "" }}DispatchFailureRate
          expr: |
            sum(rate(samba_requests_total{upstream="{{ $upstream }}",outcome=~"error|timeout"}[15m]))
              /
            sum(rate(samba_requests_total{upstream="{{ $upstream }}"}[15m])) > 0.5
          for: 15m
          labels:
            severity: warning
            component: {{ $fullname }}
            upstream: {{ $upstream | quote }}
          annotations:
            summary: {{ $fullname }} dispatch failure rate >50%
            description: |
              More than half of {{ $upstream }} dispatches errored over
              the last 15m. Likely auth, DNS, or NATS connection issue.
              Not rate-limit pressure (those return 200 with low Remaining).
                kubectl logs -n {{ "{{" }} $labels.namespace {{ "}}" }} deploy/{{ $fullname }}
            runbook_url: https://runbooks.pleme.io/rate-limit/{{ $upstream }}-dispatch-errors

        - alert: {{ $fullname | title | replace "-" "" }}RateLimitPressure
          # Sustained low headroom — adaptive backoff is already kicking
          # in, but operator should know we're under pressure.
          expr: |
            avg_over_time(samba_rate_limit_remaining{upstream="{{ $upstream }}"}[15m])
              < ({{ .Values.queueWorker.upstream.budgetPerHour }} * 0.10)
          for: 30m
          labels:
            severity: warning
            component: {{ $fullname }}
            upstream: {{ $upstream | quote }}
          annotations:
            summary: {{ $upstream }} rate-limit headroom < 10% of budget
            description: |
              Average X-RateLimit-Remaining over the last 15m is below
              10% of the {{ $upstream }} budget ({{ .Values.queueWorker.upstream.budgetPerHour }}/hr).
              Adaptive backoff keeps us within share, but if persistent
              consider lowering rateLimit.requestsPerMinute or finding
              other callers consuming the same credential.
            runbook_url: https://runbooks.pleme.io/rate-limit/{{ $upstream }}-pressure

    - name: {{ $fullname }}.queue
      interval: 1m
      rules:
        - alert: {{ $fullname | title | replace "-" "" }}QueueGrowingUnbounded
          expr: |
            deriv(samba_queue_depth{stream="{{ $stream }}",consumer="{{ $consumer }}"}[1h]) > 5
          for: 2h
          labels:
            severity: warning
            component: {{ $fullname }}
            upstream: {{ $upstream | quote }}
          annotations:
            summary: {{ $fullname }} queue growing > 5 msg/hr for 2h
            description: |
              Stream {{ $stream }} is growing. Either a backlog spike
              (will drain over hours; OK) or a sustained imbalance
              (publishers > drain rate). If samba_pace_factor is < 1
              persistently, upstream rate-limit pressure is artificially
              limiting drain.
            runbook_url: https://runbooks.pleme.io/rate-limit/{{ $upstream }}-queue
{{- end }}
{{- end }}
