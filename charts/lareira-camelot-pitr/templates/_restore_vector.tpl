{{/*
camelot-pitr.restoreVector — the camelot restore VECTOR as engine extraResources (§2.4).

camelot has NO RDS. Instead of restoreToPointInTime, camelot clones a CSI VolumeSnapshot
of the durable gp3 MySQL PVC into a new PVC and stands up an ephemeral restore
StatefulSet on it. The engine emits these verbatim (provider-kubernetes Objects), then
runs the generic canary/verify Jobs against a temporary restore saas wired to it. These
are Helm-templated into input.extraResources — the engine has ZERO knowledge of shape.

TIER-HONEST: snapshot-point recovery (the snapshot cadence), NOT arbitrary-second PITR
— binlog replay forward (restore.binlogReplay) is DESIGN/M3. LIVE reconcile is
OPERATOR-GATED on Crossplane + provider-kubernetes + a CSI VolumeSnapshotClass.
*/}}
{{- define "camelot-pitr.restoreVector" -}}
{{- $r := .Values.restore -}}
{{- if $r.enabled -}}
{{- /*
  The restore server mounts a datadir snapshotted from the SOURCE server, so
  their versions are ONE decision. Enforced at render rather than documented,
  because both failure modes are silent until a drill actually runs.
*/ -}}
{{- $wantTag := $r.sourceMysqlTag | required "restore.sourceMysqlTag is required: it declares the SOURCE mysql version the snapshot comes from (akeyless-mysql-pleme's image.tag), which the restore server must match." -}}
{{- $gotTag := (splitList ":" $r.mysqlImage) | last -}}
{{- if ne $gotTag $wantTag -}}
{{- fail (printf "restore.mysqlImage=%q must be tag %q to match restore.sourceMysqlTag: the restore server mounts a datadir snapshotted from the source server, so a major.minor mismatch is a broken drill, not a preference. MySQL 8.4 additionally ships mysql_native_password DISABLED by default, and camelot-bootstrap sets root@%% to exactly that plugin (caching_sha2 breaks the akeyless driver), so a restored root account cannot authenticate at all. Change both together, or change neither." $r.mysqlImage $wantTag) -}}
{{- end -}}
{{- if $r.createSnapshot }}
# (optional) snapshot the live gp3 PVC now — the drill smoke path (snap-now → restore-now).
# For a true point-in-time, set createSnapshot:false + snapshotName to a pre-existing
# scheduled snapshot at/before restoreTime.
- apiVersion: snapshot.storage.k8s.io/v1
  kind: VolumeSnapshot
  metadata:
    name: {{ $r.restoreStatefulSetName }}-snap
    namespace: {{ .Release.Namespace }}
    labels:
      camelot.pleme.io/surface: pitr
      camelot.pleme.io/ephemeral: "true"
  spec:
    volumeSnapshotClassName: {{ $r.snapshotClassName | quote }}
    source:
      persistentVolumeClaimName: {{ $r.sourcePvcName | quote }}
{{- end }}
# the restore PVC — cloned from the (pre-existing OR just-created) VolumeSnapshot.
- apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: {{ $r.restorePvcName }}
    namespace: {{ .Release.Namespace }}
    labels:
      camelot.pleme.io/surface: pitr
      camelot.pleme.io/ephemeral: "true"
  spec:
    accessModes: ["ReadWriteOnce"]
    storageClassName: {{ $r.storageClassName | quote }}
    dataSource:
      apiGroup: snapshot.storage.k8s.io
      kind: VolumeSnapshot
      name: {{ $r.snapshotName | default (printf "%s-snap" $r.restoreStatefulSetName) | quote }}
    resources:
      requests:
        storage: {{ $r.size | quote }}
# the ephemeral restore MySQL StatefulSet — bound to the restored PVC, on role: camelot.
- apiVersion: apps/v1
  kind: StatefulSet
  metadata:
    name: {{ $r.restoreStatefulSetName }}
    namespace: {{ .Release.Namespace }}
    labels:
      camelot.pleme.io/surface: pitr
      camelot.pleme.io/ephemeral: "true"
      app.kubernetes.io/name: {{ $r.restoreStatefulSetName }}
  spec:
    replicas: 1
    serviceName: {{ $r.restoreStatefulSetName }}
    selector:
      matchLabels:
        app.kubernetes.io/name: {{ $r.restoreStatefulSetName }}
    template:
      metadata:
        labels:
          app.kubernetes.io/name: {{ $r.restoreStatefulSetName }}
          camelot.pleme.io/surface: pitr
      spec:
        nodeSelector:
          {{- toYaml .Values.nodeSelector | nindent 10 }}
        tolerations:
          {{- toYaml .Values.tolerations | nindent 10 }}
        containers:
          - name: mysql
            image: {{ $r.mysqlImage | quote }}
            env:
              - name: MYSQL_ALLOW_EMPTY_PASSWORD
                value: "1"
            ports:
              - containerPort: 3306
            volumeMounts:
              - name: data
                mountPath: /var/lib/mysql
        volumes:
          - name: data
            persistentVolumeClaim:
              claimName: {{ $r.restorePvcName }}
{{- end -}}
{{- end -}}
