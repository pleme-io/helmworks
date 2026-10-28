{{- define "pleme-lib.runtime.kind" -}}
{{- $k := (.Values.runtime).kind | default "native" -}}
{{- if not (has $k (list "native" "wasm")) -}}
{{- fail (printf "runtime.kind is %q; it is native or wasm" (toString $k)) -}}
{{- end -}}
{{- $k -}}
{{- end }}

{{- define "pleme-lib.runtimeclass" -}}
{{- if eq (include "pleme-lib.runtime.kind" .) "wasm" -}}
runtimeClassName: {{ (.Values.runtime).class | default "wasm" }}
{{- end -}}
{{- end }}

{{- define "pleme-lib.wasm-component.validate" -}}
{{- $kind := include "pleme-lib.runtime.kind" . -}}
{{- $r := .Values.runtime | default dict -}}
{{- $reason := toString ($r.reason | default "") -}}
{{- if and $reason (not (has $reason (list "process" "host_program" "device"))) -}}
{{- fail (printf "runtime.reason is %q; a native fallback names its WASI gap: process, host_program or device" $reason) -}}
{{- end -}}
{{- if eq $kind "wasm" -}}
{{- if $reason -}}
{{- fail (printf "runtime.reason is %q and runtime.kind is wasm; a reason names why a service runs native, so drop it or set runtime.kind native" $reason) -}}
{{- end -}}
{{- $c := $r.component | default dict -}}
{{- $closure := toString ($c.closure | default "") -}}
{{- if not $closure -}}
{{- fail "runtime.component.closure is required when runtime.kind is wasm; it is the /nix/store path that holds the component" -}}
{{- end -}}
{{- if not (hasPrefix "/nix/store/" $closure) -}}
{{- fail (printf "runtime.component.closure %q is not under /nix/store/; a wasm pod runs a component from a nix closure" $closure) -}}
{{- end -}}
{{- if contains ".." $closure -}}
{{- fail (printf "runtime.component.closure %q contains \"..\"; name the closure path itself" $closure) -}}
{{- end -}}
{{- range $f := list "path" "app" -}}
{{- $v := toString (get $c $f | default "") -}}
{{- if and $v (or (hasPrefix "/" $v) (contains ".." $v)) -}}
{{- fail (printf "runtime.component.%s %q must be a relative path inside the closure, with no \"..\"" $f $v) -}}
{{- end -}}
{{- end -}}
{{- with (.Values.access).exec -}}
{{- fail (printf "access.exec is %s; a wasm component cannot run a program; set runtime.kind native with reason process" (toJson .)) -}}
{{- end -}}
{{- if .Values.command -}}
{{- fail "runtime.kind is wasm and command is set; the component is the program, pass its arguments in args" -}}
{{- end -}}
{{- if eq (toString (.Values.health).type) "Exec" -}}
{{- fail "health.type is Exec and runtime.kind is wasm; a component's probes are httpGet" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.wasm-component.image" -}}
{{- if eq (include "pleme-lib.runtime.kind" .) "wasm" -}}
{{- include "pleme-lib.wasm-component.validate" . -}}
nix:{{ .Values.runtime.component.closure }}
{{- end -}}
{{- end }}

{{- define "pleme-lib.wasm-component.access" -}}
{{- $ctx := .ctx -}}
{{- $a := $ctx.Values.access | default dict -}}
{{- $egress := list -}}
{{- range $i, $e := ($a.egress | default list) -}}
{{- if kindIs "string" $e -}}
{{- $egress = append $egress $e -}}
{{- else -}}
{{- if not $e.host -}}
{{- fail (printf "access.egress[%d] (%s) names no host; a wasm component dials host:port, so give the binding its host" $i (toString $e.binding)) -}}
{{- end -}}
{{- $egress = append $egress (printf "%s:%d" $e.host (int $e.port)) -}}
{{- end -}}
{{- end -}}
{{- range $i, $e := (.extraEgress | default list) -}}
{{- if not (and (kindIs "string" $e) (regexMatch "^[A-Za-z0-9.-]+:[0-9]{1,5}$" (toString $e))) -}}
{{- fail (printf "extraEgress[%d] is %q; an extra peer is host:port" $i (toString $e)) -}}
{{- end -}}
{{- $egress = append $egress $e -}}
{{- end -}}
{{- $reads := list -}}
{{- range $r := ($a.reads | default list) -}}
{{- $reads = append $reads (toString $r.path) -}}
{{- end -}}
{{- range $e := (include "pleme-lib.secret-ref.entries" $ctx | fromYamlArray) -}}
{{- $reads = append $reads (toString $e.path) -}}
{{- end -}}
{{- range $m := ($ctx.Values.volumeMounts | default list) -}}
{{- if $m.readOnly -}}
{{- $reads = append $reads (toString $m.mountPath) -}}
{{- end -}}
{{- end -}}
{{- $writes := list -}}
{{- range $w := ($a.writes | default list) -}}
{{- if kindIs "map" $w -}}
{{- $writes = append $writes (toString $w.path) -}}
{{- else -}}
{{- $writes = append $writes (toString $w) -}}
{{- end -}}
{{- end -}}
{{- $listen := list -}}
{{- range $p := ($a.listen | default list) -}}
{{- $listen = append $listen (int $p) -}}
{{- end -}}
{{- if not $listen -}}
{{- range $p := ($ctx.Values.ports | default list) -}}
{{- with $p.containerPort -}}
{{- $listen = append $listen (int .) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $effects := $a.effects | default (list "network" "clock" "entropy" "environment") -}}
{{- $out := dict "effects" $effects "egress" (uniq $egress) "reads" (uniq $reads) "writes" (uniq $writes) "exec" ($a.exec | default list) -}}
{{- with $listen -}}
{{- $_ := set $out "listen" (uniq .) -}}
{{- end -}}
{{- toJson $out -}}
{{- end }}

{{- define "pleme-lib.wasm-component.annotations" -}}
{{- $ctx := .ctx -}}
{{- include "pleme-lib.wasm-component.validate" $ctx -}}
{{- if eq (include "pleme-lib.runtime.kind" $ctx) "wasm" -}}
{{- $c := $ctx.Values.runtime.component | default dict -}}
blue.pleme.io/access: {{ include "pleme-lib.wasm-component.access" . | quote }}
{{- with $c.path }}
{{- if ne . "component.wasm" }}
wasm.pleme.io/component: {{ . | quote }}
{{- end }}
{{- end }}
{{- with $c.app }}
wasm.pleme.io/app: {{ . | quote }}
{{- end }}
{{- else -}}
{{- with ($ctx.Values.runtime).reason -}}
blue.pleme.io/native-because: {{ . | quote }}
{{- end -}}
{{- end -}}
{{- end }}
