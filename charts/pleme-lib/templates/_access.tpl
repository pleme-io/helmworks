{{/*
pleme-lib: access — a blue service's access posture, rendered

The values block mirrors blue's `access` field (blue/docs/SERVICE-ACCESS.md):
the peers a service may reach, the paths it reads at boot, and the paths it
writes. Each list is the whole allowance. An absent `access` renders nothing
and changes nothing, so no existing consumer moves.

  pleme-lib.access-networkpolicy  deny-all + DNS + one egress allow per peer,
                                  rendered by pleme-lib.networkpolicy.v1 and
                                  its derivedAllow; no second generator
  pleme-lib.access-volumes        the pod volumes for reads and writes
  pleme-lib.access-volumes.mounts the matching container volumeMounts
  pleme-lib.access.validate       every refusal, named by the key that fixes it

pleme-lib.deployment appends the volumes and mounts when `access` is set.

VALUES
  access:
    egress:
      - binding: database           a binding the service declares
        host: kensa-pg-rw           <svc> | <svc>.<ns>.svc[.<domain>]
        port: 5432
        protocol: TCP               optional
        namespace: ""               overrides the namespace the host names
        podLabels: {}               narrows the peer inside that namespace
        cidr: ""                    a binding outside the cluster
      - "api.github.com:443"        host:port; a public host opens that port
                                    to public addresses only, an IPv4 host
                                    opens that address alone
    reads:
      - path: /var/run/secrets/kensa
        secret: kensa-db            exactly one of secret | configMap | projected
        items: []                   optional key -> path projection
    writes:
      - /var/lib/kensa/tmp          emptyDir
      - path: /var/lib/kensa
        claimName: kensa-data       a declared PVC in place of the emptyDir
        sizeLimit: 1Gi              emptyDir only
        medium: Memory              emptyDir only

NetworkPolicy has no hostname peer. An in-cluster host resolves to its
namespace (narrowed by podLabels); a public host can only be allowed as its
port to every public address. The policy name says which host asked for it.
*/}}

{{- define "pleme-lib.access.declared" -}}
{{- if kindIs "map" .Values.access -}}true{{- end -}}
{{- end }}

{{- define "pleme-lib.access.namespaceOf" -}}
{{- $parts := splitList "." .host -}}
{{- if eq (len $parts) 1 -}}
{{- .namespace -}}
{{- else if and (ge (len $parts) 3) (eq (index $parts 2) "svc") -}}
{{- index $parts 1 -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.access.slug" -}}
{{- regexReplaceAll "[^a-z0-9-]+" (lower .) "-" | trimAll "-" | trunc 40 | trimSuffix "-" -}}
{{- end }}

{{- define "pleme-lib.access.publicPeer" -}}
cidr: 0.0.0.0/0
except:
  - 10.0.0.0/8
  - 172.16.0.0/12
  - 192.168.0.0/16
  - 169.254.0.0/16
  - 100.64.0.0/10
{{- end }}

{{- define "pleme-lib.access.egressAllow" -}}
{{- $ns := include "pleme-lib.namespace" . -}}
{{- $out := list -}}
{{- $seen := dict -}}
{{- range $i, $e := ((.Values.access).egress | default list) -}}
{{- $rule := dict -}}
{{- if kindIs "string" $e -}}
  {{- $m := regexFindAll "^([A-Za-z0-9.-]+):([0-9]{1,5})$" $e -1 -}}
  {{- if not $m -}}
    {{- fail (printf "access.egress[%d] is %q; a string peer is host:port, for example \"api.github.com:443\"" $i $e) -}}
  {{- end -}}
  {{- $host := regexReplaceAll ":[0-9]+$" $e "" -}}
  {{- $port := regexReplaceAll "^.*:" $e "" | atoi -}}
  {{- if or (lt $port 1) (gt $port 65535) -}}
    {{- fail (printf "access.egress[%d] is %q; the port is outside 1-65535" $i $e) -}}
  {{- end -}}
  {{- $peerNs := include "pleme-lib.access.namespaceOf" (dict "host" $host "namespace" $ns) -}}
  {{- $_ := set $rule "name" (printf "peer-%s-%d" (include "pleme-lib.access.slug" $host) $port) -}}
  {{- $_ := set $rule "ports" (list (dict "port" $port "protocol" "TCP")) -}}
  {{- if regexMatch "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$" $host -}}
    {{- $_ := set $rule "cidr" (printf "%s/32" $host) -}}
  {{- else if $peerNs -}}
    {{- $_ := set $rule "namespace" $peerNs -}}
  {{- else -}}
    {{- $rule = merge $rule (include "pleme-lib.access.publicPeer" . | fromYaml) -}}
  {{- end -}}
{{- else if kindIs "map" $e -}}
  {{- range $k, $_ := $e -}}
    {{- if not (has $k (list "binding" "host" "port" "protocol" "namespace" "podLabels" "cidr")) -}}
      {{- fail (printf "access.egress[%d].%s is not a peer field; a binding peer takes binding, host, port, protocol, namespace, podLabels or cidr" $i $k) -}}
    {{- end -}}
  {{- end -}}
  {{- if not $e.binding -}}
    {{- fail (printf "access.egress[%d].binding is required; a peer with no binding has no typed owner (blue refuses it too)" $i) -}}
  {{- end -}}
  {{- if not $e.port -}}
    {{- fail (printf "access.egress[%d] (%s) names no port; an omitted port opens every port to the peer" $i $e.binding) -}}
  {{- end -}}
  {{- $_ := set $rule "name" (printf "binding-%s" (include "pleme-lib.access.slug" $e.binding)) -}}
  {{- $_ := set $rule "ports" (list (dict "port" $e.port "protocol" ($e.protocol | default "TCP"))) -}}
  {{- if $e.cidr -}}
    {{- if or $e.namespace $e.podLabels -}}
      {{- fail (printf "access.egress[%d] (%s) sets cidr beside namespace or podLabels; one peer is either an address or a selector" $i $e.binding) -}}
    {{- end -}}
    {{- $_ := set $rule "cidr" $e.cidr -}}
  {{- else -}}
    {{- $peerNs := $e.namespace | default (include "pleme-lib.access.namespaceOf" (dict "host" ($e.host | default "") "namespace" $ns)) -}}
    {{- if not $peerNs -}}
      {{- fail (printf "access.egress[%d] (%s) host %q is not an in-cluster service name (<svc> or <svc>.<ns>.svc); set namespace, or cidr for an address outside the cluster" $i $e.binding ($e.host | default "")) -}}
    {{- end -}}
    {{- $_ := set $rule "namespace" $peerNs -}}
    {{- with $e.podLabels -}}
      {{- $_ := set $rule "podLabels" . -}}
    {{- end -}}
  {{- end -}}
{{- else -}}
  {{- fail (printf "access.egress[%d] is neither a binding map nor a host:port string" $i) -}}
{{- end -}}
{{- if hasKey $seen $rule.name -}}
  {{- fail (printf "access.egress[%d] repeats the peer %q; declare each peer once" $i $rule.name) -}}
{{- end -}}
{{- $_ := set $seen $rule.name true -}}
{{- $out = append $out $rule -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}

{{- define "pleme-lib.access-networkpolicy" -}}
{{- if include "pleme-lib.access.declared" . -}}
{{- include "pleme-lib.access.validate" . -}}
{{- $np := include "pleme-lib.networkpolicy.values" . | fromYaml -}}
{{- $allow := deepCopy ($np.allow | default dict) -}}
{{- $egress := concat ($allow.egress | default list) (include "pleme-lib.access.egressAllow" . | fromYamlArray) -}}
{{- $_ := set $allow "egress" $egress -}}
{{- $_ := set $np "allow" $allow -}}
{{- $_ := set $np "enabled" true -}}
{{- $_ := set $np "allowDns" true -}}
{{- $vals := omit .Values "networkPolicy" -}}
{{- $_ := set $vals "networkPolicy" $np -}}
{{- $ctx := dict "Values" $vals "Release" .Release "Chart" .Chart "Capabilities" .Capabilities "Template" .Template "Files" .Files -}}
{{ include "pleme-lib.networkpolicy.v1" $ctx }}
{{- end -}}
{{- end }}

{{- define "pleme-lib.access.reads" -}}
{{- $out := list -}}
{{- range $i, $r := ((.Values.access).reads | default list) -}}
{{- if not (kindIs "map" $r) -}}
  {{- fail (printf "access.reads[%d] is %q with no source; a read is {path, secret | configMap | projected}, because a path alone has nothing to mount" $i (toString $r)) -}}
{{- end -}}
{{- range $k, $_ := $r -}}
  {{- if not (has $k (list "path" "secret" "configMap" "projected" "items")) -}}
    {{- fail (printf "access.reads[%d].%s is not a read field; a read takes path, secret, configMap, projected or items" $i $k) -}}
  {{- end -}}
{{- end -}}
{{- $sources := 0 -}}
{{- range $k := list "secret" "configMap" "projected" -}}
  {{- if hasKey $r $k -}}{{- $sources = add1 $sources -}}{{- end -}}
{{- end -}}
{{- if ne $sources 1 -}}
  {{- fail (printf "access.reads[%d] (%s) declares %d sources; set exactly one of secret, configMap or projected" $i ($r.path | default "") $sources) -}}
{{- end -}}
{{- $out = append $out (dict "name" (printf "access-read-%d" $i) "path" $r.path "spec" $r) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}

{{- define "pleme-lib.access.writes" -}}
{{- $out := list -}}
{{- range $i, $w := ((.Values.access).writes | default list) -}}
{{- $spec := ternary $w (dict "path" $w) (kindIs "map" $w) -}}
{{- range $k, $_ := $spec -}}
  {{- if not (has $k (list "path" "claimName" "sizeLimit" "medium")) -}}
    {{- fail (printf "access.writes[%d].%s is not a write field; a write takes path, claimName, sizeLimit or medium" $i $k) -}}
  {{- end -}}
{{- end -}}
{{- if and $spec.claimName (or $spec.sizeLimit $spec.medium) -}}
  {{- fail (printf "access.writes[%d] (%s) sets claimName beside sizeLimit or medium; those shape an emptyDir, and a claim is sized by the PVC" $i ($spec.path | default "")) -}}
{{- end -}}
{{- $out = append $out (dict "name" (printf "access-write-%d" $i) "path" $spec.path "spec" $spec) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}

{{- define "pleme-lib.access.validate" -}}
{{- if include "pleme-lib.access.declared" . -}}
{{- range $k, $_ := .Values.access -}}
  {{- if not (has $k (list "egress" "reads" "writes" "effects" "listen" "exec")) -}}
    {{- fail (printf "access.%s is not an access field; access takes egress, reads, writes, effects, listen and exec" $k) -}}
  {{- end -}}
{{- end -}}
{{- range $i, $e := (.Values.access.effects | default list) -}}
  {{- if not (has (toString $e) (list "network" "filesystem" "clock" "entropy" "environment" "process")) -}}
    {{- fail (printf "access.effects[%d] is %q; an effect is network, filesystem, clock, entropy, environment or process" $i (toString $e)) -}}
  {{- end -}}
{{- end -}}
{{- range $i, $p := (.Values.access.listen | default list) -}}
  {{- if or (not (or (kindIs "float64" $p) (kindIs "int64" $p) (kindIs "int" $p))) (lt (int $p) 1) (gt (int $p) 65535) -}}
    {{- fail (printf "access.listen[%d] is %v; a listen port is an integer in 1-65535" $i $p) -}}
  {{- end -}}
{{- end -}}
{{- range $i, $x := (.Values.access.exec | default list) -}}
  {{- if not (kindIs "string" $x) -}}
    {{- fail (printf "access.exec[%d] is %v; an exec entry names a program" $i $x) -}}
  {{- end -}}
{{- end -}}
{{- $_ := include "pleme-lib.access.egressAllow" . -}}
{{- $seen := dict -}}
{{- $entries := concat (include "pleme-lib.access.reads" . | fromYamlArray) (include "pleme-lib.access.writes" . | fromYamlArray) (include "pleme-lib.secret-ref.entries" . | fromYamlArray) -}}
{{- range $e := $entries -}}
  {{- $p := toString ($e.path | default "") -}}
  {{- if not (hasPrefix "/" $p) -}}
    {{- fail (printf "%s path %q is not absolute; a mount point is an absolute path" $e.name $p) -}}
  {{- end -}}
  {{- if or (eq $p "/nix/store") (hasPrefix "/nix/store/" $p) -}}
    {{- fail (printf "%s path %q is under /nix/store, which the image owns; it is not a mount point" $e.name $p) -}}
  {{- end -}}
  {{- $p = trimSuffix "/" $p -}}
  {{- if hasKey $seen $p -}}
    {{- fail (printf "%s and %s both mount %q; one path is read or written, never both" (get $seen $p) $e.name $p) -}}
  {{- end -}}
  {{- $_ := set $seen $p $e.name -}}
{{- end -}}
{{- $sc := .Values.securityContext | default dict -}}
{{- if and (hasKey $sc "readOnlyRootFilesystem") (not $sc.readOnlyRootFilesystem) -}}
  {{- fail "access is declared and securityContext.readOnlyRootFilesystem is false; access.writes is the whole writable set, so the root filesystem stays read-only" -}}
{{- end -}}
{{- range $i, $m := (.Values.volumeMounts | default list) -}}
  {{- if not $m.readOnly -}}
    {{- fail (printf "volumeMounts[%d] (%s) is writable beside a declared access; declare the path in access.writes, or set readOnly: true" $i ($m.mountPath | default "")) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.access-volumes" -}}
{{- if include "pleme-lib.access.declared" . -}}
{{- include "pleme-lib.access.validate" . -}}
{{- $out := list -}}
{{- range $r := (include "pleme-lib.access.reads" . | fromYamlArray) -}}
{{- $s := $r.spec -}}
{{- $v := dict "name" $r.name -}}
{{- if $s.secret -}}
  {{- $src := dict "secretName" $s.secret -}}
  {{- with $s.items -}}{{- $_ := set $src "items" . -}}{{- end -}}
  {{- $_ := set $v "secret" $src -}}
{{- else if $s.configMap -}}
  {{- $src := dict "name" $s.configMap -}}
  {{- with $s.items -}}{{- $_ := set $src "items" . -}}{{- end -}}
  {{- $_ := set $v "configMap" $src -}}
{{- else -}}
  {{- $_ := set $v "projected" $s.projected -}}
{{- end -}}
{{- $out = append $out $v -}}
{{- end -}}
{{- range $w := (include "pleme-lib.access.writes" . | fromYamlArray) -}}
{{- $s := $w.spec -}}
{{- if $s.claimName -}}
  {{- $out = append $out (dict "name" $w.name "persistentVolumeClaim" (dict "claimName" $s.claimName)) -}}
{{- else -}}
  {{- $ed := dict -}}
  {{- with $s.medium -}}{{- $_ := set $ed "medium" . -}}{{- end -}}
  {{- with $s.sizeLimit -}}{{- $_ := set $ed "sizeLimit" . -}}{{- end -}}
  {{- $out = append $out (dict "name" $w.name "emptyDir" $ed) -}}
{{- end -}}
{{- end -}}
{{- with $out -}}{{- toYaml . -}}{{- end -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.access-volumes.mounts" -}}
{{- if include "pleme-lib.access.declared" . -}}
{{- $out := list -}}
{{- range $r := (include "pleme-lib.access.reads" . | fromYamlArray) -}}
{{- $out = append $out (dict "name" $r.name "mountPath" $r.path "readOnly" true) -}}
{{- end -}}
{{- range $w := (include "pleme-lib.access.writes" . | fromYamlArray) -}}
{{- $out = append $out (dict "name" $w.name "mountPath" $w.path) -}}
{{- end -}}
{{- with $out -}}{{- toYaml . -}}{{- end -}}
{{- end -}}
{{- end }}
