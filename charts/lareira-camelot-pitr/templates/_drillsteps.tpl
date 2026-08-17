{{/*
camelot-pitr.drillSteps — the ordered drill steps as engine DrillSteps (config, not code).

Each step runs the generic pitr-tools binary (images.pitrTools, by digest) as a Job with
the step's command/args; the engine substitutes the runtime {{placeholder}} vocabulary
({{correlationId}} / {{restoreNamespace}} / {{secretPaths}} / …). Store-neutral: the
binaries hit camelot's OWN in-cluster store via jobEnv creds (external-secrets.yaml).
*/}}
{{- define "camelot-pitr.drillSteps" -}}
{{- $d := .Values.drillSteps -}}
{{- if $d.canaryCreate }}
- name: canary-create
  phase: Restoring
  command: ["/canary-create"]
  args:
    - --secret-paths={{ "{{secretPaths}}" }}
    - --correlation-id={{ "{{correlationId}}" }}
{{- end }}
{{- if $d.verify }}
- name: verify
  phase: Verifying
  command: ["/verify"]
  args:
    - --secret-paths={{ "{{secretPaths}}" }}
    - --restore-namespace={{ "{{restoreNamespace}}" }}
    - --correlation-id={{ "{{correlationId}}" }}
  initContainers:
    - name: wait-for-restore-deps
      command: ["/wait-for-deps"]
      args:
        - --namespace={{ "{{restoreNamespace}}" }}
        - --max-wait={{ $d.waitVerifyMaxWait }}
        - --poll-interval={{ $d.waitPollInterval }}
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
    - --restore-namespace={{ "{{restoreNamespace}}" }}
    - --correlation-id={{ "{{correlationId}}" }}
    - --diagnostics-bucket={{ "{{diagnosticsBucket}}" }}
{{- end }}
{{- end -}}
