{{- /*
pleme-lareira.vmStack — the abstracted VictoriaMetrics stack composition.

M2 of the abstracted-VM goal: VictoriaMetrics expressed FULLY in pleme-io
helmworks primitives, in the same WHAT-from-typed-values / HOW-via-pleme-lib
abstracted style as pleme-vector. This template fans a single typed `.Values.vm.*`
border out to the pleme-lib VM CRD family (_vm.tpl, pleme-lib >= 0.23.0):

    vm.single        → pleme-lib.vmSingle   (metric store; storage invariant)
    vm.cluster       → pleme-lib.vmCluster  (HA topology)
    vm.agent         → pleme-lib.vmAgent    (scrape + remote-write)
    vm.alert         → pleme-lib.vmAlert    (rule evaluation)
    vm.alertmanager  → pleme-lib.vmAlertmanager
    vm.auth          → pleme-lib.vmAuth
    vm.rules         → pleme-lib.vmRule              (alert WHAT, as a CR)
    vm.alertmanagerConfig → pleme-lib.vmAlertmanagerConfig  (ntfy routing tree as a CR)
    vm.podScrapes    → pleme-lib.vmPodScrape   (map → N)
    vm.nodeScrapes   → pleme-lib.vmNodeScrape  (map → N)

Like every lareira composition it is gated on the master `.Values.enabled`
toggle (default-off), and each component is independently gated on its own
`.enabled` so a partial stack renders only what is on. The VM operator owns the
workload pods + PVCs (VMSingle.spec.storage) — this template owns the typed
DECLARATION, not the runtime. Pair with `templates/all.yaml`:

    {{ include "pleme-lareira.allResources" . }}
    {{ include "pleme-lareira.vmStack" . }}
*/ -}}

{{- define "pleme-lareira.vmStack" -}}
{{- if include "pleme-lareira.enabled" . }}
{{- if ((.Values.vm).single).enabled }}
---
{{- include "pleme-lib.vmSingle" . }}
{{- end }}
{{- if ((.Values.vm).cluster).enabled }}
---
{{- include "pleme-lib.vmCluster" . }}
{{- end }}
{{- if ((.Values.vm).agent).enabled }}
---
{{- include "pleme-lib.vmAgent" . }}
{{- end }}
{{- if ((.Values.vm).alert).enabled }}
---
{{- include "pleme-lib.vmAlert" . }}
{{- end }}
{{- if ((.Values.vm).alertmanager).enabled }}
---
{{- include "pleme-lib.vmAlertmanager" . }}
{{- end }}
{{- if ((.Values.vm).auth).enabled }}
---
{{- include "pleme-lib.vmAuth" . }}
{{- end }}
{{- if ((.Values.vm).rules).enabled }}
---
{{- include "pleme-lib.vmRule" . }}
{{- end }}
{{- if ((.Values.vm).alertmanagerConfig).enabled }}
---
{{- include "pleme-lib.vmAlertmanagerConfig" . }}
{{- end }}
{{- if (.Values.vm).podScrapes }}
{{- include "pleme-lib.vmPodScrape" . }}
{{- end }}
{{- if (.Values.vm).nodeScrapes }}
{{- include "pleme-lib.vmNodeScrape" . }}
{{- end }}
{{- end }}
{{- end -}}
