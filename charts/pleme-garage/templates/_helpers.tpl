{{/*
Garage-specific helpers. Generic naming/labels live in pleme-lib.
*/}}

{{/* Render the garage.toml from values.garage.* */}}
{{- define "pleme-garage.config" -}}
metadata_dir = "{{ .Values.garage.metadataDir }}"
data_dir     = "{{ .Values.garage.dataDir }}"

replication_mode = "{{ .Values.garage.replicationMode }}"
block_size       = {{ .Values.garage.blockSize }}
compression_level = {{ .Values.garage.compressionLevel }}

# rpc_secret is read from the file referenced below (Garage native).
rpc_secret_file = "/etc/garage/secrets/{{ .Values.garage.rpc.secretKey }}"
rpc_bind_addr   = "{{ .Values.garage.rpc.bindAddr }}"
# rpc_public_addr is set per-pod via $POD_IP at startup (see args).

[s3_api]
api_bind_addr = "{{ .Values.garage.s3Api.bindAddr }}"
s3_region     = "{{ .Values.garage.s3Api.region }}"
root_domain   = "{{ .Values.garage.s3Api.rootDomain }}"

{{- if .Values.garage.s3Web.enabled }}
[s3_web]
bind_addr      = "{{ .Values.garage.s3Web.bindAddr }}"
root_domain    = "{{ .Values.garage.s3Web.rootDomain }}"
index          = "{{ .Values.garage.s3Web.indexDocument }}"
{{- end }}

[admin]
api_bind_addr      = "{{ .Values.garage.admin.bindAddr }}"
admin_token_file   = "/etc/garage/secrets/{{ .Values.garage.admin.adminTokenSecretKey }}"
metrics_token_file = "/etc/garage/secrets/{{ .Values.garage.admin.metricsTokenSecretKey }}"

{{- if .Values.garage.extraConfig }}

# --- extraConfig ---
{{ .Values.garage.extraConfig }}
{{- end }}
{{- end }}
