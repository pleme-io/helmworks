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
{{- $wantTag := $r.sourceMysqlTag | required "restore.sourceMysqlTag is required: it declares the SOURCE mysql version the snapshot comes from (the source MySQL subchart's image.tag), which the restore server must match." -}}
{{- $gotTag := (splitList ":" $r.mysqlImage) | last -}}
{{- if ne $gotTag $wantTag -}}
{{- fail (printf "restore.mysqlImage=%q must be tag %q to match restore.sourceMysqlTag: the restore server mounts a datadir snapshotted from the source server, so a major.minor mismatch is a broken drill, not a preference. MySQL 8.4 additionally ships mysql_native_password DISABLED by default, and camelot-bootstrap sets root@%% to exactly that plugin (caching_sha2 breaks the app's MySQL driver), so a restored root account cannot authenticate at all. Change both together, or change neither." $r.mysqlImage $wantTag) -}}
{{- end -}}
{{/*
★ EVERY NAMESPACE BELOW IS THE RUNTIME {{restoreNamespace}}, NOT .Release.Namespace.
   The value is QUOTED, and that is not style: unquoted, YAML reads
   `{{restoreNamespace}}` as a nested flow mapping and the render dies with
   "invalid map key: map[interface{}]interface{}". The drill steps get away
   without quotes only because there the placeholder sits inside a longer string.
   Changed 2026-08-18. It was `.Release.Namespace` — helm-static, baked at chart
   render — and that was wrong in a way nothing reported.

   The engine substitutes {{restoreNamespace}} into every string of every
   extraResource (pitr-tools function/extra.go, substituteDeep), and its own
   comment describes the wrapped manifests as "already carrying
   metadata.namespace = restore-<corr> via the {{restoreNamespace}} substitution".
   This chart was the outlier: its drill STEPS used the runtime placeholder while
   its restore VECTOR used the release namespace, so a drill with a supplied
   restore namespace put the restored MySQL in one namespace and looked for the
   SaaS to verify in another.

   Nothing errors in that state. The snapshot binds, the PVC binds, the
   StatefulSet runs, and every object reports Healthy — the restored database
   simply is not where anything expects it. It is also what would have silently
   defeated viveiro's `spec.pitr.wireSaas`, which points the environment's confs
   at camelot-mysql-restore.<env-namespace>.svc.cluster.local.

   And it makes the CSI constraint self-satisfying rather than a hazard to
   remember: VolumeSnapshot is Namespaced and a PVC's dataSource is a
   TypedLocalObjectReference, so snapshot and clone MUST share a namespace. With
   one placeholder driving all four, they cannot diverge.

   CONSEQUENCE for `createSnapshot: true`: `restore.sourcePvcName` must now name a
   PVC in the RESTORE namespace, not the release namespace. A viveiro environment
   is RAMDISK — its MySQL is memory-backed and has no PVC at all — so that path
   cannot apply there. Such a drill uses `createSnapshot: false` with
   `snapshotName` naming a pre-provisioned VolumeSnapshot in the restore
   namespace, bound to a cluster-scoped VolumeSnapshotContent produced from the
   real source. That is the supported cross-namespace shape, and it still requires
   the source PVC to be CSI-backed — camelot's `data-mysql-0` is in-tree gp2
   today (7 of 9 PVs are), which is tracked separately.
   `pending-pitr-source-csi:`
*/}}
{{- if $r.createSnapshot }}
# (optional) snapshot the live gp3 PVC now — the drill smoke path (snap-now → restore-now).
# For a true point-in-time, set createSnapshot:false + snapshotName to a pre-existing
# scheduled snapshot at/before restoreTime.
- apiVersion: snapshot.storage.k8s.io/v1
  kind: VolumeSnapshot
  metadata:
    name: {{ $r.restoreStatefulSetName }}-snap
    namespace: "{{ "{{restoreNamespace}}" }}"
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
    namespace: "{{ "{{restoreNamespace}}" }}"
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
    namespace: "{{ "{{restoreNamespace}}" }}"
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
# ★ THE RESTORE MySQL'S SERVICE. Added 2026-08-18 — it was MISSING, and its absence
# is why nothing could ever reach the restored database.
#
# EMITTED LAST, after the StatefulSet, purely to keep the existing positional
# assertions in tests/camelot_pitr_test.yaml valid — extraResources are indexed by
# position there. Order carries no meaning to the engine: each entry becomes an
# independent provider-kubernetes Object and Kubernetes has no Service-before-
# StatefulSet requirement (a StatefulSet names its governing Service; it does not
# wait on it).
#
# The StatefulSet below declares `serviceName: <restoreStatefulSetName>` and no
# Service by that name was ever emitted. A StatefulSet does not create its governing
# Service; it only names one, and Kubernetes does not complain when the name resolves
# to nothing. So the restore plane came up healthy, the PVC bound, MySQL started, and
# the restored data had no DNS name any client could use. Same shape as every other
# defect found this session: the declaration was present and correct, and the thing
# that makes it reachable was absent.
#
# Headless (clusterIP: None) because it governs a StatefulSet: that gives the stable
# per-pod DNS a StatefulSet's identity contract is built on, and a restore server is
# addressed as one specific instance, never load-balanced across replicas.
#
# The NAME is deliberately `restore.mysqlServiceName`, defaulting to the same value
# the StatefulSet's serviceName uses, rather than being hardcoded: a consumer whose
# conf renderer expects the database at a fixed name (camelot-bootstrap's
# EnvSpec.MysqlHost is ONE field — `db_host_name for every service`) points the whole
# SaaS at the restored database by setting this to what that renderer already emits,
# instead of re-rendering every service's conf.
- apiVersion: v1
  kind: Service
  metadata:
    name: {{ $r.mysqlServiceName | default $r.restoreStatefulSetName }}
    namespace: "{{ "{{restoreNamespace}}" }}"
    labels:
      camelot.pleme.io/surface: pitr
      camelot.pleme.io/ephemeral: "true"
  spec:
    clusterIP: None
    selector:
      app.kubernetes.io/name: {{ $r.restoreStatefulSetName }}
    ports:
      - name: mysql
        port: 3306
        targetPort: 3306
        protocol: TCP
{{- end -}}
{{- end -}}
