{{- define "empresa-site.prefixPath" -}}
{{- trimPrefix "/" .Values.pathPrefix -}}
{{- end }}

{{- define "empresa-site.values" -}}
{{- $port := int .Values.service.port -}}
{{- $placeholder := .Values.content.placeholder.enabled -}}
{{- if and (not $placeholder) (not .Values.content.image.repository) -}}
{{- fail "content.image.repository is required when content.placeholder.enabled is false" -}}
{{- end -}}
{{- $image := ternary .Values.server.image .Values.content.image $placeholder -}}
image:
  repository: {{ $image.repository | quote }}
  tag: {{ $image.tag | quote }}
  pullPolicy: {{ .Values.server.pullPolicy }}
nameOverride: {{ .Values.nameOverride | quote }}
fullnameOverride: {{ .Values.fullnameOverride | quote }}
replicaCount: {{ .Values.replicaCount }}
imagePullSecrets: {{ toJson .Values.imagePullSecrets }}
nodeSelector: {{ toJson .Values.nodeSelector }}
resources:
  {{- toYaml .Values.resources | nindent 2 }}
automountServiceAccountToken: false
serviceAccount:
  create: true
  automountServiceAccountToken: false
ports:
  - name: http
    containerPort: {{ $port }}
    protocol: TCP
  - name: health
    containerPort: {{ add1 $port }}
    protocol: TCP
service:
  ports:
    - name: http
      port: {{ $port }}
      targetPort: http
      protocol: TCP
health:
  path: /health/live
  readyPath: /health/ready
  port: health
  livenessInitialDelay: 2
  livenessPeriod: 10
  readinessInitialDelay: 1
  readinessPeriod: 5
startupProbe:
  enabled: true
  path: /health/startup
  port: health
  initialDelaySeconds: 1
  periodSeconds: 2
  failureThreshold: 15
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  fsGroup: 65532
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
volumeMounts:
  - name: hanabi-config
    mountPath: /etc/hanabi
    readOnly: true
  - name: tmp
    mountPath: /tmp
  {{- if $placeholder }}
  - name: placeholder
    mountPath: /app/static
    readOnly: true
  {{- end }}
volumes:
  - name: hanabi-config
    configMap:
      name: {{ include "pleme-lib.fullname" . }}-hanabi
  - name: tmp
    emptyDir:
      sizeLimit: 16Mi
  {{- if $placeholder }}
  - name: placeholder
    configMap:
      name: {{ include "pleme-lib.fullname" . }}-placeholder
      items:
        - key: index.html
          path: index.html
        {{- if ne .Values.pathPrefix "/" }}
        - key: index.html
          path: {{ include "empresa-site.prefixPath" . }}/index.html
        {{- end }}
  {{- end }}
{{- end }}

{{- define "empresa-site.target" -}}
{{- printf "http://%s.%s.svc:%d" (include "pleme-lib.fullname" .) (include "pleme-lib.namespace" .) (int .Values.service.port) -}}
{{- end }}
