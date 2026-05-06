{
  description = "Helmworks: reusable Helm chart library for pleme-io internal services";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    substrate = {
      url = "github:pleme-io/substrate/321b5027f27fe867aa4f6dc7a0d4c355e70848f7";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    forge = {
      url = "github:pleme-io/forge/65225fd";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
      inputs.substrate.follows = "substrate";
      inputs.crate2nix.follows = "crate2nix";
    };
    crate2nix = {
      url = "github:nix-community/crate2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, substrate, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.devenv.flakeModule ];

      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      perSystem = { pkgs, system, ... }:
        let
          helm = pkgs.kubernetes-helm;

          substrateLib = substrate.libFor {
            inherit pkgs system;
            forge = inputs.forge.packages.${system}.default;
          };

          chartDefs = [
            { name = "pleme-lib"; chartDir = ./charts/pleme-lib; }
            { name = "pleme-compliance"; chartDir = ./charts/pleme-compliance; }
            { name = "pleme-admission-policies"; chartDir = ./charts/pleme-admission-policies; }
            { name = "pleme-zot"; chartDir = ./charts/pleme-zot; }
            { name = "pleme-image-sync"; chartDir = ./charts/pleme-image-sync; }
            { name = "pleme-lareira"; chartDir = ./charts/pleme-lareira; }
            { name = "pleme-lareira-canary"; chartDir = ./charts/pleme-lareira-canary; }
            { name = "pleme-microservice"; chartDir = ./charts/pleme-microservice; }
            { name = "pleme-worker"; chartDir = ./charts/pleme-worker; }
            { name = "pleme-web"; chartDir = ./charts/pleme-web; }
            { name = "pleme-cronjob"; chartDir = ./charts/pleme-cronjob; }
            { name = "pleme-migration"; chartDir = ./charts/pleme-migration; }
            { name = "pleme-operator"; chartDir = ./charts/pleme-operator; }
            { name = "pleme-namespace"; chartDir = ./charts/pleme-namespace; }
            { name = "pleme-statefulset"; chartDir = ./charts/pleme-statefulset; }
            { name = "pleme-database"; chartDir = ./charts/pleme-database; }
            { name = "pleme-cache"; chartDir = ./charts/pleme-cache; }
            { name = "pleme-bootstrap"; chartDir = ./charts/pleme-bootstrap; }
            # ── ARC (GitHub Actions Runner Controller) ──
            { name = "pleme-arc-controller"; chartDir = ./charts/pleme-arc-controller; }
            { name = "pleme-arc-runner-pool"; chartDir = ./charts/pleme-arc-runner-pool; }
            # ── pleme-lareira home-services consumers (rio cluster) ──
            # Family Tier 1 — broadest household value
            { name = "lareira-vaultwarden"; chartDir = ./charts/lareira-vaultwarden; }
            { name = "lareira-immich"; chartDir = ./charts/lareira-immich; }
            { name = "lareira-jellyfin"; chartDir = ./charts/lareira-jellyfin; }
            { name = "lareira-paperless"; chartDir = ./charts/lareira-paperless; }
            { name = "lareira-adguard"; chartDir = ./charts/lareira-adguard; }
            { name = "lareira-home-assistant"; chartDir = ./charts/lareira-home-assistant; }
            { name = "lareira-ntfy"; chartDir = ./charts/lareira-ntfy; }
            # Family Tier 2 — quality-of-life household services
            { name = "lareira-joplin"; chartDir = ./charts/lareira-joplin; }
            { name = "lareira-audiobookshelf"; chartDir = ./charts/lareira-audiobookshelf; }
            { name = "lareira-calibre-web"; chartDir = ./charts/lareira-calibre-web; }
            { name = "lareira-kavita"; chartDir = ./charts/lareira-kavita; }
            { name = "lareira-komga"; chartDir = ./charts/lareira-komga; }
            { name = "lareira-mealie"; chartDir = ./charts/lareira-mealie; }
            { name = "lareira-linkding"; chartDir = ./charts/lareira-linkding; }
            { name = "lareira-miniflux"; chartDir = ./charts/lareira-miniflux; }
            { name = "lareira-stirling-pdf"; chartDir = ./charts/lareira-stirling-pdf; }
            { name = "lareira-frigate"; chartDir = ./charts/lareira-frigate; }
            { name = "lareira-cups"; chartDir = ./charts/lareira-cups; }
            # Creative cousin — movie producer surface
            { name = "lareira-postgres"; chartDir = ./charts/lareira-postgres; }
            { name = "lareira-stash"; chartDir = ./charts/lareira-stash; }
            { name = "lareira-resourcespace"; chartDir = ./charts/lareira-resourcespace; }
            { name = "lareira-screener-delivery"; chartDir = ./charts/lareira-screener-delivery; }
            # Creative wife — children's-book author surface
            { name = "lareira-forgejo"; chartDir = ./charts/lareira-forgejo; }
            { name = "lareira-hedgedoc"; chartDir = ./charts/lareira-hedgedoc; }
            { name = "lareira-outline"; chartDir = ./charts/lareira-outline; }
            { name = "lareira-penpot"; chartDir = ./charts/lareira-penpot; }
            { name = "lareira-listmonk"; chartDir = ./charts/lareira-listmonk; }
            { name = "lareira-cal-com"; chartDir = ./charts/lareira-cal-com; }
            { name = "lareira-pandoc-render"; chartDir = ./charts/lareira-pandoc-render; }
            { name = "hanabi"; chartDir = ./charts/hanabi; }
            { name = "shinka"; chartDir = ./charts/shinka; }
            { name = "kenshi"; chartDir = ./charts/kenshi; }
            { name = "arachne"; chartDir = ./charts/arachne; }
            { name = "sekiban"; chartDir = ./charts/sekiban; }
            { name = "pleme-gpu-workload"; chartDir = ./charts/pleme-gpu-workload; }
            { name = "pleme-wasm"; chartDir = ./charts/pleme-wasm; }
            { name = "wasm-operator"; chartDir = ./charts/wasm-operator; }
            { name = "headscale"; chartDir = ./charts/headscale; }
            { name = "iac-forge"; chartDir = ./charts/iac-forge; }
            { name = "pleme-shinryu"; chartDir = ./charts/pleme-shinryu; }
            { name = "pleme-attic"; chartDir = ./charts/pleme-attic; }
            { name = "pleme-tatara-operator"; chartDir = ./charts/pleme-tatara-operator; }
            { name = "pleme-tend-operator"; chartDir = ./charts/pleme-tend-operator; }
            { name = "pleme-tend-throttle"; chartDir = ./charts/pleme-tend-throttle; }
            { name = "pleme-nats"; chartDir = ./charts/pleme-nats; }
            { name = "pleme-nix-builder"; chartDir = ./charts/pleme-nix-builder; }
            { name = "pleme-sui"; chartDir = ./charts/pleme-sui; }
            { name = "convergence-controller"; chartDir = ./charts/convergence-controller; }
            { name = "pangea-operator"; chartDir = ./charts/pangea-operator; }
            { name = "pleme-garage"; chartDir = ./charts/pleme-garage; }
            { name = "pleme-ocis"; chartDir = ./charts/pleme-ocis; }
            { name = "pleme-cnpg"; chartDir = ./charts/pleme-cnpg; }
            { name = "pleme-cnpg-cluster"; chartDir = ./charts/pleme-cnpg-cluster; }
            { name = "pleme-cnpg-restore"; chartDir = ./charts/pleme-cnpg-restore; }
            { name = "lareira-authentik"; chartDir = ./charts/lareira-authentik; }
            # ── openclaw skill-store ecosystem ──
            { name = "lareira-openclaw"; chartDir = ./charts/lareira-openclaw; }
            { name = "lareira-openclaw-pki"; chartDir = ./charts/lareira-openclaw-pki; }
            { name = "lareira-cartorio"; chartDir = ./charts/lareira-cartorio; }
            { name = "lareira-lacre"; chartDir = ./charts/lareira-lacre; }
            { name = "lareira-openclaw-store"; chartDir = ./charts/lareira-openclaw-store; }
            { name = "lareira-openclaw-scanner"; chartDir = ./charts/lareira-openclaw-scanner; }
            { name = "lareira-openclaw-stack"; chartDir = ./charts/lareira-openclaw-stack; }
          ];

          # Use substrate's mkHelmAllApps for all chart lifecycle apps
          helmApps = substrateLib.mkHelmAllApps {
            charts = chartDefs;
            libChartDir = ./charts/pleme-lib;
            registry = "oci://ghcr.io/pleme-io/charts";
          };

          # Build chart tarballs as Nix packages (for CI caching)
          chartPackages = substrateLib.mkHelmChartPackages {
            charts = chartDefs;
            libChartDir = ./charts/pleme-lib;
          };

          # ── openclaw stack e2e harness ──
          # Three layers, each `nix run`-able:
          #
          #   stack:render — render the umbrella with synthetic
          #     attestation values; pass/fail on helm template alone.
          #     No cluster required.
          #
          #   stack:unittest — run every helm-unittest spec under
          #     tests/lareira-* (cartorio, lacre, openclaw-pki,
          #     openclaw-store, openclaw-scanner, openclaw-stack).
          #     Pure rendering invariants. No cluster.
          #
          #   stack:e2e — bring up an ephemeral k3d cluster, helm-install
          #     the umbrella with compliance.enforce=false, wait for all
          #     pods Ready, smoke-test cartorio /health + /merkle/root +
          #     lacre /health, then tear down. Real cluster.
          mkApp = name: script: {
            type = "app";
            program = toString (pkgs.writeShellScript "openclaw-${name}" ''
              set -euo pipefail
              export PATH="${pkgs.lib.makeBinPath ([
                helm
                pkgs.kubectl
                pkgs.curl
                pkgs.jq
                pkgs.coreutils
                pkgs.git
                pkgs.docker-client
              ] ++ pkgs.lib.optionals (system == "x86_64-linux" || system == "aarch64-linux") [
                pkgs.k3d
              ])}:$PATH"
              cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              ${script}
            '');
          };

          # Synthetic-but-valid attestation values for render-only paths.
          # The chart validators require non-empty signature + hashes; these
          # satisfy the shape gate without claiming real CI provenance.
          renderArgs = pkgs.lib.concatStringsSep " " (
            (pkgs.lib.flatten (map (sub: [
              "--set ${sub}.pleme-microservice.image.tag=sha256:abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
              "--set ${sub}.pleme-microservice.attestation.signature=fake"
              "--set ${sub}.pleme-microservice.attestation.certificationHash=fake"
              "--set ${sub}.pleme-microservice.attestation.complianceHash=fake"
              "--set ${sub}.pleme-microservice.attestation.changesetHash=fake"
            ]) [ "pki" "registry" "gate" "store" "scanner" ])) ++ [
              "--set backingRegistry.image.tag=sha256:abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
              "--set backingRegistry.attestation.enabled=true"
              "--set backingRegistry.attestation.signature=fake"
              "--set backingRegistry.attestation.certificationHash=fake"
              "--set backingRegistry.attestation.complianceHash=fake"
              "--set backingRegistry.attestation.changesetHash=fake"
            ]
          );

          stackApps = {
            "stack:render" = mkApp "stack-render" ''
              echo "==> rendering lareira-openclaw-stack with all 6 sub-charts"
              cd charts/lareira-openclaw-stack
              helm dep update >/dev/null
              helm template t . ${renderArgs} > /tmp/openclaw-stack.yaml
              echo ""
              echo "Resources rendered:"
              grep "^kind:" /tmp/openclaw-stack.yaml | sort | uniq -c
              echo ""
              echo "==> render OK"
            '';

            "stack:unittest" = mkApp "stack-unittest" ''
              echo "==> running helm-unittest across every lareira-* chart"
              for chart in lareira-cartorio lareira-lacre lareira-openclaw-pki lareira-openclaw-store lareira-openclaw-scanner lareira-openclaw-stack; do
                echo ""
                echo "── $chart ──"
                if [ -d tests/$chart ]; then
                  ( cd charts/$chart && helm dep update >/dev/null 2>&1 || true )
                  ( cd charts/$chart && helm unittest -f "../../tests/$chart/*_test.yaml" . )
                else
                  echo "  (no tests/$chart — skipping)"
                fi
              done
              echo ""
              echo "==> unittest OK"
            '';

            "stack:e2e" = mkApp "stack-e2e" ''
              if ! command -v k3d >/dev/null 2>&1; then
                echo "stack:e2e requires k3d on PATH. The flake includes it for"
                echo "linux hosts; on darwin install via 'brew install k3d' or"
                echo "run this app on a CI runner that bundles k3d."
                exit 1
              fi
              CLUSTER="openclaw-e2e-$$"
              cleanup() {
                k3d cluster delete "$CLUSTER" 2>/dev/null || true
              }
              trap cleanup EXIT

              echo "==> creating ephemeral k3d cluster '$CLUSTER'"
              k3d cluster create "$CLUSTER" --wait --timeout 120s
              export KUBECONFIG="$(k3d kubeconfig write "$CLUSTER")"

              echo "==> creating openclaw namespace"
              kubectl create namespace openclaw

              echo "==> installing lareira-openclaw-stack (compliance.enforce=false)"
              cd charts/lareira-openclaw-stack
              helm dep update >/dev/null

              # Disable enforcement (and sekiban CRDs) so the e2e doesn't
              # need a co-installed sekiban/kensa stack. The proof
              # invariants are tested separately via helm-unittest.
              ENFORCE_OFF=$(for s in pki registry gate store scanner; do
                echo -n "--set $s.pleme-microservice.compliance.enforce=false "
                echo -n "--set $s.sekiban.enabled=false "
                echo -n "--set $s.pleme-microservice.attestation.enabled=false "
              done)

              helm install openclaw-stack . \
                --namespace openclaw \
                ${renderArgs} \
                $ENFORCE_OFF \
                --set backingRegistry.attestation.enabled=false \
                --wait --timeout 300s

              echo "==> waiting for all pods Ready"
              kubectl -n openclaw wait --for=condition=Ready pod --all --timeout=180s

              echo "==> smoking cartorio /health + /merkle/root"
              kubectl -n openclaw port-forward svc/openclaw-stack-registry-cartorio 18082:8082 >/dev/null 2>&1 &
              PF1=$!
              sleep 3
              curl -fsS "http://127.0.0.1:18082/health"
              echo ""
              curl -fsS "http://127.0.0.1:18082/api/v1/merkle/root" | jq .
              kill $PF1 2>/dev/null || true

              echo "==> smoking lacre /health"
              kubectl -n openclaw port-forward svc/openclaw-stack-gate-lacre 18083:8083 >/dev/null 2>&1 &
              PF2=$!
              sleep 3
              curl -fsS "http://127.0.0.1:18083/health"
              echo ""
              kill $PF2 2>/dev/null || true

              echo ""
              echo "==> stack:e2e OK ✓"
            '';
          };

        in {
          packages = chartPackages;
          apps = helmApps // stackApps;

          devShells.default = pkgs.mkShell {
            packages = [
              helm
              pkgs.kubectl
              pkgs.yq-go
            ];
          };
        };
    };
}
