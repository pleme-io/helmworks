{{/*
pleme-lareira.pvc — ZFS-backed PersistentVolumeClaim.

Emits a PVC bound to the local-path StorageClass (which on rio points at
/var/lib/k3s-storage on the ZFS pool/k3s dataset). Optional nodeName pin
keeps the PVC bound to the right node on multi-node clusters; on rio
(single node) it's a no-op but harmless.

The .Values.persistence.zfsDataset hint is informational — surfaced via
labels so the alert layer can route PVC-near-full alerts to a "which
dataset is filling up?" view. It does NOT change provisioning.

Use in consumer chart templates/pvc.yaml:

  {{- if include "pleme-lareira.enabled" . }}
  {{- include "pleme-lareira.pvc" . }}
  {{- end }}

The matching volumeMount + volume snippets are emitted by
`pleme-lareira.pvc.volumeMount` / `pleme-lareira.pvc.volume` below for
consumers that don't construct their own Pod spec.
*/}}

{{- define "pleme-lareira.pvc" -}}
{{- if .Values.persistence.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ $fullname }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    pleme.io/zfs-dataset: {{ .Values.persistence.zfsDataset | replace "/" "-" | quote }}
  annotations:
    pleme.io/zfs-dataset: {{ .Values.persistence.zfsDataset | quote }}
    {{- with .Values.persistence.nodeName }}
    pleme.io/pinned-node: {{ . | quote }}
    {{- end }}
spec:
  accessModes:
    {{- toYaml .Values.persistence.accessModes | nindent 4 }}
  storageClassName: {{ .Values.persistence.storageClass | quote }}
  resources:
    requests:
      storage: {{ .Values.persistence.size | quote }}
{{- end }}
{{- end -}}

{{/*
pleme-lareira.pvc.volume — Pod volume entry for the PVC. Use in consumer
volumes list:

  volumes:
    {{- include "pleme-lareira.pvc.volume" . | nindent 4 }}
*/}}
{{- define "pleme-lareira.pvc.volume" -}}
{{- if .Values.persistence.enabled }}
- name: data
  persistentVolumeClaim:
    claimName: {{ include "pleme-lib.fullname" . }}
{{- end }}
{{- end -}}

{{/*
pleme-lareira.pvc.volumeMount — Container volumeMount entry. Use in
consumer container's volumeMounts list:

  volumeMounts:
    {{- include "pleme-lareira.pvc.volumeMount" . | nindent 12 }}
*/}}
{{- define "pleme-lareira.pvc.volumeMount" -}}
{{- if .Values.persistence.enabled }}
- name: data
  mountPath: {{ .Values.persistence.mountPath | quote }}
  {{- with .Values.persistence.subPath }}
  subPath: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end -}}
