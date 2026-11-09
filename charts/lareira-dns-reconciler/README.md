# lareira-dns-reconciler

Helm chart deploying the
[`dns-reconciler`](https://github.com/pleme-io/programs/tree/main/dns-reconciler)
tatara-lisp program.

Replaces ExternalDNS. ~80 lines of tatara-lisp + this chart's ~30
lines of values, vs ExternalDNS's ~50K lines of Go.

The DnsReconciler policy CR (which records to create) is operator-edited.

## Install

```sh
helm install dns-reconciler ./charts/lareira-dns-reconciler \
  --namespace tatara-system --create-namespace \
  --set 'pleme-computeunit.enabled=true'
```

## See also

- [`pleme-computeunit`](../pleme-computeunit/) — library chart
