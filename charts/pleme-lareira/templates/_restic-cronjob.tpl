{{- /*
pleme-lareira.restic.cronjob

Restic backup CronJob mounting the consumer's PVC read-only and running
`restic backup` followed by `restic forget --prune`.

Credentials come from the Secret named in
.Values.backup.repositoryEnvFrom.secretName, which must contain at minimum
RESTIC_PASSWORD and RESTIC_REPOSITORY plus any backend creds (AWS, B2, R2,
etc).

Optional verify CronJob runs `restic check --read-data-subset` on a
separate (less frequent) schedule when .Values.backup.verify.enabled is
true.

See README for usage examples.
*/ -}}

{{- define "pleme-lareira.restic.cronjob" -}}
{{- if and .Values.backup.enabled .Values.persistence.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $secret := required "backup.enabled=true requires backup.repositoryEnvFrom.secretName" .Values.backup.repositoryEnvFrom.secretName }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ $fullname }}-backup
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    pleme.io/component: backup
spec:
  schedule: {{ .Values.backup.schedule | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        metadata:
          labels:
            {{- include "pleme-lib.selectorLabels" . | nindent 12 }}
            pleme.io/component: backup
        spec:
          restartPolicy: OnFailure
          serviceAccountName: {{ include "pleme-lib.serviceAccountName" . }}
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
          containers:
            - name: restic
              image: "{{ .Values.backup.image.repository }}:{{ .Values.backup.image.tag }}"
              imagePullPolicy: {{ .Values.backup.image.pullPolicy }}
              command:
                - /bin/sh
                - -c
                - |
                  set -euo pipefail
                  echo "[restic] backup starting at $(date -Iseconds)"
                  restic snapshots >/dev/null 2>&1 || restic init
                  restic backup {{ join " " .Values.backup.paths }} \
                    --tag chart={{ include "pleme-lib.name" . }} \
                    --tag release={{ .Release.Name }} \
                    --tag namespace={{ include "pleme-lib.namespace" . }}
                  restic forget --prune \
                    --keep-daily {{ .Values.backup.retention.daily }} \
                    --keep-weekly {{ .Values.backup.retention.weekly }} \
                    --keep-monthly {{ .Values.backup.retention.monthly }} \
                    --keep-yearly {{ .Values.backup.retention.yearly }}
                  echo "[restic] backup ok at $(date -Iseconds)"
              envFrom:
                - secretRef:
                    name: {{ $secret | quote }}
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop:
                    - ALL
              resources:
                {{- toYaml .Values.backup.resources | nindent 16 }}
              volumeMounts:
                - name: data
                  mountPath: /data
                  readOnly: true
                - name: cache
                  mountPath: /cache
                - name: tmp
                  mountPath: /tmp
              env:
                - name: RESTIC_CACHE_DIR
                  value: /cache
                - name: TMPDIR
                  value: /tmp
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: {{ $fullname }}
                readOnly: true
            - name: cache
              emptyDir:
                sizeLimit: 1Gi
            - name: tmp
              emptyDir:
                sizeLimit: 256Mi
{{- if .Values.backup.verify.enabled }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ $fullname }}-backup-verify
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    pleme.io/component: backup-verify
spec:
  schedule: {{ .Values.backup.verify.schedule | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: {{ include "pleme-lib.serviceAccountName" . }}
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
          containers:
            - name: restic-verify
              image: "{{ .Values.backup.image.repository }}:{{ .Values.backup.image.tag }}"
              imagePullPolicy: {{ .Values.backup.image.pullPolicy }}
              command:
                - /bin/sh
                - -c
                - |
                  set -euo pipefail
                  echo "[restic] verify starting at $(date -Iseconds)"
                  restic check --read-data-subset {{ .Values.backup.verify.readDataSubset | quote }}
                  echo "[restic] verify ok at $(date -Iseconds)"
              envFrom:
                - secretRef:
                    name: {{ $secret | quote }}
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop:
                    - ALL
              resources:
                {{- toYaml .Values.backup.resources | nindent 16 }}
              volumeMounts:
                - name: cache
                  mountPath: /cache
                - name: tmp
                  mountPath: /tmp
              env:
                - name: RESTIC_CACHE_DIR
                  value: /cache
                - name: TMPDIR
                  value: /tmp
          volumes:
            - name: cache
              emptyDir:
                sizeLimit: 1Gi
            - name: tmp
              emptyDir:
                sizeLimit: 256Mi
{{- end }}
{{- end }}
{{- end -}}
