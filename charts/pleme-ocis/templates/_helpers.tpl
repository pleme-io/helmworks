{{/*
oCIS-specific helpers. Generic naming/labels live in pleme-lib.
*/}}

{{/*
Render the env block that configures oCIS. oCIS is configured almost
entirely via env vars — see https://doc.owncloud.com/ocis/next/deployment/services/env-vars.html
*/}}
{{- define "pleme-ocis.envVars" -}}
- name: OCIS_URL
  value: {{ .Values.ocis.url | quote }}
- name: OCIS_LOG_LEVEL
  value: {{ .Values.ocis.logLevel | default "info" | quote }}
- name: OCIS_LOG_COLOR
  value: {{ .Values.ocis.logColor | quote }}
- name: OCIS_LOG_PRETTY
  value: {{ .Values.ocis.logPretty | quote }}
- name: OCIS_INSECURE
  value: {{ .Values.ocis.insecure | quote }}
{{- if .Values.ocis.insecure }}
# Plain HTTP everywhere — no internal self-signed cert. Required when
# the service sits behind a TLS-terminating proxy (Cloudflared, ingress
# controller, etc.) and you don't want the proxy to bear with cert
# verification.
- name: PROXY_TLS
  value: "false"
- name: PROXY_HTTP_ADDR
  value: "0.0.0.0:9200"
- name: OCIS_LDAP_URI
  value: "ldap://localhost:9235"
{{- end }}
- name: OCIS_BASE_DATA_PATH
  value: {{ .Values.ocis.storage.localBaseDir | quote }}
- name: OCIS_CONFIG_DIR
  value: {{ printf "%s/config" .Values.ocis.storage.localBaseDir | quote }}
{{- /* Initial admin */}}
- name: IDM_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ required "ocis.admin.passwordSecretName is required" .Values.ocis.admin.passwordSecretName }}
      key: {{ .Values.ocis.admin.passwordSecretKey }}
- name: OCIS_ADMIN_USER_ID
  value: {{ .Values.ocis.admin.userName | quote }}
{{- /* IDP / Konnect / inter-service signing */}}
- name: OCIS_JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ required "ocis.idp.secretName is required" .Values.ocis.idp.secretName }}
      key: {{ .Values.ocis.idp.jwtSecretKey }}
- name: OCIS_MACHINE_AUTH_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.ocis.idp.secretName }}
      key: {{ .Values.ocis.idp.machineAuthApiKey }}
- name: OCIS_TRANSFER_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.ocis.idp.secretName }}
      key: {{ .Values.ocis.idp.revaTransferSecret }}
- name: OCIS_SYSTEM_USER_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.ocis.idp.secretName }}
      key: {{ .Values.ocis.idp.storageSystemSecret }}
- name: OCIS_SYSTEM_USER_ID
  value: {{ .Values.ocis.idp.secretName }}-system-user
- name: IDP_ENCRYPTION_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.ocis.idp.secretName }}
      key: {{ .Values.ocis.idp.konnectEncryptionSecret }}
- name: IDP_SIGNING_KID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.ocis.idp.secretName }}
      key: {{ .Values.ocis.idp.konnectSigningKey }}
{{- /* Storage backend */}}
- name: STORAGE_USERS_DRIVER
  value: {{ .Values.ocis.storage.backend | quote }}
{{- if eq .Values.ocis.storage.backend "s3ng" }}
- name: STORAGE_USERS_S3NG_ENDPOINT
  value: {{ .Values.ocis.storage.s3.endpoint | quote }}
- name: STORAGE_USERS_S3NG_REGION
  value: {{ .Values.ocis.storage.s3.region | quote }}
- name: STORAGE_USERS_S3NG_BUCKET
  value: {{ .Values.ocis.storage.s3.bucket | quote }}
- name: STORAGE_USERS_S3NG_FORCE_PATH_STYLE
  value: {{ .Values.ocis.storage.s3.forcePathStyle | quote }}
- name: STORAGE_USERS_S3NG_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ required "ocis.storage.s3.credentialsSecretName is required" .Values.ocis.storage.s3.credentialsSecretName }}
      key: {{ .Values.ocis.storage.s3.accessKeyKey }}
- name: STORAGE_USERS_S3NG_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.ocis.storage.s3.credentialsSecretName }}
      key: {{ .Values.ocis.storage.s3.secretKeyKey }}
{{- end }}
{{- if .Values.ocis.tracing.enabled }}
- name: OCIS_TRACING_ENABLED
  value: "true"
- name: OCIS_TRACING_ENDPOINT
  value: {{ .Values.ocis.tracing.endpoint | quote }}
- name: OCIS_TRACING_COLLECTOR
  value: {{ .Values.ocis.tracing.collector | quote }}
{{- end }}
{{- end }}
