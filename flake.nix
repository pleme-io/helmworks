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
            { name = "pleme-cnpg-cluster"; chartDir = ./charts/pleme-cnpg-cluster; }
            { name = "pleme-cnpg-restore"; chartDir = ./charts/pleme-cnpg-restore; }
            { name = "lareira-authentik"; chartDir = ./charts/lareira-authentik; }
            # ── openclaw skill-store ecosystem ──
            { name = "lareira-openclaw"; chartDir = ./charts/lareira-openclaw; }
            { name = "lareira-openclaw-pki"; chartDir = ./charts/lareira-openclaw-pki; }
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

        in {
          packages = chartPackages;
          apps = helmApps;

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
