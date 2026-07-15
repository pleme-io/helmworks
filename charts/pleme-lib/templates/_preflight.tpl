{{/*
pleme-lib: preflight init container

Produces:
  pleme-lib.preflightInitContainer — a light init check that verifies a
  service's DECLARED come-up requirements (db reachable + required tables,
  tcp deps host:port, mounted secrets) BEFORE the app container starts, so a
  missing requirement holds the pod in Init with a clear report instead of
  letting the app crashloop against a dependency that hasn't opened its port
  yet (the "TCP dial refused" startup-race class of bug — a dependent
  service's own bounded app-level retry gives up before the real dependency
  finishes coming up, exits non-zero, and relies on Kubernetes' restart to
  eventually land on a lucky timing window).

Image: ghcr.io/pleme-io/preflight — the Nix-built Go keyway tool. `check`
reads the typed spec from PREFLIGHT_SPEC (JSON) and exits 0 (met) / 1 (unmet)
/ 2 (tool error). The DB password is NEVER in the spec — inject it through
preflight.extraEnv (secretKeyRef).

Gated by .Values.preflight.enabled. Output is a single list item (- name: ...).
Runs before pleme-lib.shinkaWaitInitContainer in the pod's initContainers list
(pleme-lib._deployment.tpl) — preflight confirms raw reachability, shinkaWait
then waits for migration state, so the two compose in causal order.
*/}}
{{- define "pleme-lib.preflightInitContainer" -}}
{{- if (.Values.preflight).enabled }}
- name: preflight
  image: {{ .Values.preflight.image | default "ghcr.io/pleme-io/preflight:amd64-latest" }}
  imagePullPolicy: {{ .Values.preflight.imagePullPolicy | default "IfNotPresent" }}
  args: ["check"]
  env:
    - name: PREFLIGHT_SPEC
      value: {{ .Values.preflight.spec | default dict | toJson | quote }}
    {{- with .Values.preflight.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.preflight.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  resources:
    {{- toYaml (.Values.preflight.resources | default (dict "requests" (dict "cpu" "10m" "memory" "16Mi") "limits" (dict "cpu" "100m" "memory" "32Mi"))) | nindent 4 }}
{{- end }}
{{- end }}
