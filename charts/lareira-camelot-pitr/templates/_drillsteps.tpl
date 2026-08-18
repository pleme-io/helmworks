{{/*
camelot-pitr.drillSteps — the ordered drill steps as engine DrillSteps (config, not code).

Each step runs the generic pitr-tools binary (images.pitrTools, by digest) as a Job with
the step's command/args; the engine substitutes the runtime {{placeholder}} vocabulary
({{correlationId}} / {{restoreNamespace}} / {{secretPaths}} / …). Store-neutral: the
binaries hit camelot's OWN in-cluster store via jobEnv creds (external-secrets.yaml).

★ ARGS CORRECTED 2026-08-18 AGAINST THE REAL BINARIES. Every step below previously
passed at least one flag its binary does not define, and Go's `flag` package exits 2
on an unknown flag BEFORE any work — so no drill step had ever executed. The chart
rendered green and its unit tests passed the whole time, because nothing compared the
emitted args against the binaries that receive them. `camelot_pitr_test.yaml` now
asserts exactly that; see its flag-contract case.

Verified per-binary from pitr-tools/cmd/*, not from the shared flag vocabulary (a flag
defined in one binary is not available in another — that is precisely how this drifted):

  /canary-create      borealis-access-id, correlation-id, source-borealis-url
  /verify             borealis-access-id, correlation-id, max-wait, mode,
                      poll-interval, restored-borealis-url, restored-uam-url,
                      secret-paths
  /wait-for-deps      correlation-id, max-restarts, max-wait, poll-interval
  /cleanup            …, correlation-id, restore-namespace, …      (was already correct)
  /diagnostic-collect correlation-id, diagnostics-bucket, extra-mr-gvrs,
                      pitrsession-name, tenant, xr-group, xr-resource, xr-version

What changed, and why each:
  canary-create      --secret-paths REMOVED (it belongs to /verify, not here) and the
                     two flags it actually requires ADDED.
  verify             --restore-namespace REMOVED (no such flag) and the restored-*
                     endpoints ADDED — without them --mode=api has nothing to call.
  wait-for-deps      --namespace REMOVED (no such flag).
  diagnostic-collect --restore-namespace REMOVED (no such flag); it identifies the
                     session by --pitrsession-name + --tenant + the xr coordinates.
  cleanup            UNCHANGED. It is the one step that was already right.

★ THREE STEP-INVENTORY QUESTIONS, SETTLED BY MEASUREMENT 2026-08-18 — so nobody
re-opens them. Two were reported as defects and are not; the third is real and
its obvious fix would break every drill.

1. `canary-delete` EXISTS IN cmd/ AND IS WIRED NOWHERE — and it must stay that
   way in this file. The leak is real: every drill writes a canary into the
   source store and nothing removes it, unbounded and invisible.

   But adding it as a drill step would DELETE THE CANARY BEFORE /verify READS IT.
   There is no step sequencing: function/jobs.go:71 emits every Job into one
   desired set, filtered only by GateOnNotification, never by Phase — the engine
   says "Crossplane applies the desired set as a whole and gives no
   intra-response sequencing". A `phase: Succeeded` label buys nothing.

   /cleanup gets away with it because it SELF-GATES: cmd/cleanup/main.go polls
   the drill-result ConfigMap for a phase before acting. `canary-delete` has zero
   such constructs (measured: 0 poll/wait/drill-result references), so it would
   race and win.

   The right home is therefore /cleanup, which already sequences correctly and
   already holds the correlation id — it needs --source-borealis-url and
   --borealis-access-id. That is blocked for the same reason its other required
   flags are: the deployed drill-step image predates the namespace-ownership
   guard. `pending-cleanup-flags` covers it.

2. `diagnostic-collect` RUNNING ON SUCCESSFUL DRILLS IS DELIBERATE, not a missing
   gate. Its own header: "On phase=Succeeded: minimal proof bundle (manifest +
   pitrsession + retrieved-secrets describe). On phase=Failed (or any
   non-Succeeded): full bundle." It reads the phase off PITRSession.status and
   adjusts. Gating it out of successful drills would DELETE the proof bundle a
   passing drill produces.

3. THE EMPTY `--diagnostics-bucket` IS NOT A BROKEN UPLOAD. The flag's own help
   text reads "S3 bucket for future upload (deferred to v0.4.0; informational
   only here)". Nothing uploads, so nothing needs S3 credentials, and the absence
   of a role-arn on the job ServiceAccount costs nothing today. It becomes real
   when v0.4.0 lands.

--mode is passed EXPLICITLY even though `api` is already the binary's default
(cmd/verify/main.go:56). The two modes are not interchangeable — `presence` never reads
the secret back and exits 0 even on failure — so which one a drill ran is worth being
legible at the call site rather than inherited silently.
*/}}
{{- define "camelot-pitr.drillSteps" -}}
{{- $d := .Values.drillSteps -}}
{{- $s := .Values.store -}}
{{- /* $r: the restore vector's own values — the pod-watch selector must name the
       SAME StatefulSet _restore_vector.tpl emits, so it is read from one place
       rather than retyped here. Two spellings of one name is how a selector comes
       to match nothing while looking right. */ -}}
{{- $r := .Values.restore -}}
{{- if $d.canaryCreate }}
- name: canary-create
  phase: Restoring
  command: ["/canary-create"]
  args:
    - --source-borealis-url={{ $s.sourceUrl | required "store.sourceUrl is required: /canary-create writes the canary into the SOURCE store, and with no URL it has nowhere to write. There is no runtime placeholder for it: the source store is static config, unlike the restored endpoints below which derive from the per-drill restore namespace." }}
    - --borealis-access-id={{ $s.accessId | required "store.accessId is required: both /canary-create and /verify authenticate with it." }}
    - --correlation-id={{ "{{correlationId}}" }}
{{- end }}
{{- if $d.verify }}
- name: verify
  phase: Verifying
  command: ["/verify"]
  args:
    # The restored endpoints are COMPOSED from the runtime restore namespace: the plane
    # is stood up per-drill there, so these cannot be static values. They are built
    # from PARTS rather than a printf template because Helm's lexer closes an action at
    # the first `}}` — a placeholder nested inside `printf "...%s..."` parses as a call
    # to an undefined function `restoreNamespace`, which is a render error, not a
    # silent mis-render. Parts also let a tenant with a different service naming or
    # cluster domain retarget without touching this template.
    # --restored-borealis-url is the auth microservice (/auth); --restored-uam-url is
    # the uam microservice (/describe-item). When the uam URL is empty the binary falls
    # back to the borealis one, which would silently describe items against the wrong
    # service — so both are passed explicitly.
    - --restored-borealis-url=http://{{ $s.restoredAuthService }}.{{ "{{restoreNamespace}}" }}.{{ $s.clusterDomain }}:{{ $s.restoredPort }}
    - --restored-uam-url=http://{{ $s.restoredUamService }}.{{ "{{restoreNamespace}}" }}.{{ $s.clusterDomain }}:{{ $s.restoredPort }}
    - --borealis-access-id={{ $s.accessId }}
    - --secret-paths={{ "{{secretPaths}}" }}
    - --mode={{ $d.verifyMode }}
    - --max-wait={{ $d.verifyMaxWait }}
    - --poll-interval={{ $d.waitPollInterval }}
    - --correlation-id={{ "{{correlationId}}" }}
  initContainers:
    # ★ --service WAS MISSING, and the binary refuses without it. Corrected
    # 2026-08-18. `cmd/wait-for-deps/main.go:96` exits 2 on `len(services) == 0`
    # with "at least one --service URL required" — so this initContainer failed
    # before doing any work and the verify Job it gates could never start. The
    # --max-wait / --max-restarts budget below described a wait that never
    # happened.
    #
    # (Worth stating precisely, because it was first read the other way: this is a
    # hard exit 2, not a vacuous pass. It fails loudly — but into an initContainer
    # whose failure reads as "verify is stuck pending", which is why it went
    # unnoticed.)
    #
    # The URLs are the SAME endpoints /verify then calls, with /health appended:
    # `internal/depwait.Probe` GETs the URL verbatim and appends nothing, so the
    # path belongs here. Waiting on exactly what verify will use is the point — a
    # wait against some other endpoint proves the wrong service came up.
    - name: wait-for-restore-deps
      command: ["/wait-for-deps"]
      args:
        - --service=http://{{ $s.restoredAuthService }}.{{ "{{restoreNamespace}}" }}.{{ $s.clusterDomain }}:{{ $s.restoredPort }}/health
        - --service=http://{{ $s.restoredUamService }}.{{ "{{restoreNamespace}}" }}.{{ $s.clusterDomain }}:{{ $s.restoredPort }}/health
        # Watch the restore database's pods too. Without this the step can only
        # time out: a CrashLoopBackOff restore server is indistinguishable from a
        # slow one until --max-wait elapses, which is 45m of a drill spent waiting
        # for something already dead. --max-restarts is the threshold that turns
        # that into an early, typed failure.
        - --watch-pod={{ "{{restoreNamespace}}" }}/app.kubernetes.io/name={{ $r.restoreStatefulSetName }}
        - --max-wait={{ $d.waitVerifyMaxWait }}
        - --poll-interval={{ $d.waitPollInterval }}
        - --max-restarts={{ $d.waitMaxRestarts }}
        - --correlation-id={{ "{{correlationId}}" }}
{{- end }}
{{- if $d.cleanup }}
- name: cleanup
  phase: Succeeded
  command: ["/cleanup"]
  args:
    - --restore-namespace={{ "{{restoreNamespace}}" }}
    - --correlation-id={{ "{{correlationId}}" }}
  env:
    - name: JOB_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
{{- end }}
{{- if $d.diagnosticCollect }}
- name: diagnostic-collect
  phase: Failed
  command: ["/diagnostic-collect"]
  args:
    - --pitrsession-name={{ "{{pitrSessionName}}" }}
    - --tenant={{ "{{tenant}}" }}
    - --diagnostics-bucket={{ "{{diagnosticsBucket}}" }}
    - --correlation-id={{ "{{correlationId}}" }}
{{- end }}
{{- end -}}
