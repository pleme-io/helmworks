{{/*
pleme-zot: fail-loud compliance gate for the image-shipping security posture.

Fires when you turn on FedRAMP enforcement — compliance.enforce=true AND a
FedRAMP baseline. Then a non-compliant shipping posture FAILS the render: you
cannot deploy a registry that *enforces* FedRAMP while leaving authz off,
signatures unverified, or transport in plaintext. With enforce=false (default)
or baseline:none nothing here fires, so `helm install` / template-validation
still work. Complements pleme-lib's compliance.validate (image digest-pin,
airgap, securityContext).
*/}}
{{- define "pleme-zot.security.validate" -}}
{{- $b := ((.Values.compliance).baseline) | default "none" -}}
{{- $enforce := ((.Values.compliance).enforce) | default false -}}
{{- $fedramp := or (eq $b "fedramp-moderate") (eq $b "fedramp-high") -}}
{{- if and $enforce $fedramp -}}
  {{- if not .Values.authz.enabled -}}
    {{- fail (printf "pleme-zot: compliance.baseline=%s enforce=true requires authz.enabled=true — a registry with no authorization violates AC-6 (least privilege)." $b) -}}
  {{- end -}}
  {{- if not .Values.cosign.verify -}}
    {{- fail (printf "pleme-zot: compliance.baseline=%s enforce=true requires cosign.verify=true (SI-7: serve only signature-verified images). Set cosign.verify=true + cosign.publicKeySecret." $b) -}}
  {{- end -}}
  {{- if and .Values.cosign.verify (not .Values.cosign.publicKeySecret) -}}
    {{- fail (printf "pleme-zot: compliance.baseline=%s enforce=true with cosign.verify=true requires cosign.publicKeySecret (the trust anchor)." $b) -}}
  {{- end -}}
  {{- if eq ((.Values.tls).mode | default "edge") "edge" -}}
    {{- fail (printf "pleme-zot: compliance.baseline=%s enforce=true forbids tls.mode=edge — in-cluster pulls would be plaintext (SC-8). Use tls.mode=inPod (Zot HTTPS) or mesh (mTLS)." $b) -}}
  {{- end -}}
  {{- if and (eq $b "fedramp-high") .Values.authz.anonymousReadOnly -}}
    {{- fail (printf "pleme-zot: compliance.baseline=%s enforce=true forbids authz.anonymousReadOnly=true — no anonymous access at high (AC-3)." $b) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
