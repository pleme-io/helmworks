# lareira-dns-reconciler

Helm chart deploying the
[`dns-reconciler`](https://github.com/pleme-io/programs/tree/main/dns-reconciler)
tatara-lisp program — pattern #2 from the
[cookbook](https://github.com/pleme-io/theory/blob/main/WASM-PATTERNS.md).

Replaces ExternalDNS. ~80 lines of tatara-lisp + this chart's ~30
lines of values, vs ExternalDNS's ~50K lines of Go.

The DnsReconciler policy CR (which records to create) is operator-edited.
See [`theory/LISP-YAML-CONTROLLERS.md` §II.2](https://github.com/pleme-io/theory/blob/main/LISP-YAML-CONTROLLERS.md)
for the full YAML rule shape with declarative + escape-hatch examples.

## Install

```sh
helm install dns-reconciler ./charts/lareira-dns-reconciler \
  --namespace tatara-system --create-namespace \
  --set 'pleme-computeunit.enabled=true'
```

## See also

- [`pleme-computeunit`](../pleme-computeunit/) — library chart
- [`theory/META-FRAMEWORK.md` §VII](https://github.com/pleme-io/theory/blob/main/META-FRAMEWORK.md) — promotion ladder
