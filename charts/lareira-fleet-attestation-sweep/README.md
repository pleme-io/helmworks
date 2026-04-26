# lareira-fleet-attestation-sweep

One-shot fleet attestation re-verification. Pattern from
[cookbook](https://github.com/pleme-io/theory/blob/main/WASM-PATTERNS.md)
§I (drift-detection at the attestation layer).

Useful for periodic compliance audits or after a tameshi key
rotation. The program is the `oneShot` shape — applies once, runs
once, deletes itself after 60s with a structured report on `.status`.

## Run

```sh
helm install fleet-sweep ./charts/lareira-fleet-attestation-sweep \
  --namespace tatara-system \
  --set 'pleme-computeunit.enabled=true' \
  --set 'pleme-computeunit.trigger.oneShot.args[0]=--clusters=plo,rio'

kubectl wait --for=condition=Succeeded \
  -n tatara-system computeunit/fleet-attestation-sweep --timeout=5m

kubectl get computeunit -n tatara-system fleet-attestation-sweep -o yaml
helm uninstall fleet-sweep -n tatara-system
```
