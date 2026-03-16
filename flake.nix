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
      url = "github:pleme-io/substrate/fb9cc398db7884e98dfb160daef0c4433bbc658c";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    forge = {
      url = "github:pleme-io/forge/b099c24623b6b8c8a864c8692e6e0888c91ad812";
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

      perSystem = { pkgs, system, lib, ... }:
        let
          helm = pkgs.kubernetes-helm;

          substrateLib = substrate.libFor {
            inherit pkgs system;
            forge = inputs.forge.packages.${system}.default;
          };

          chartDefs = [
            { name = "pleme-lib"; chartDir = ./charts/pleme-lib; }
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
            { name = "hanabi"; chartDir = ./charts/hanabi; }
            { name = "shinka"; chartDir = ./charts/shinka; }
            { name = "kenshi"; chartDir = ./charts/kenshi; }
            { name = "arachne"; chartDir = ./charts/arachne; }
            { name = "sekiban"; chartDir = ./charts/sekiban; }
            { name = "pleme-gpu-workload"; chartDir = ./charts/pleme-gpu-workload; }
            { name = "headscale"; chartDir = ./charts/headscale; }
            { name = "iac-forge"; chartDir = ./charts/iac-forge; }
          ];

          # Use substrate's mkHelmAllApps for all chart lifecycle apps
          helmApps = substrateLib.mkHelmAllApps {
            charts = chartDefs;
            libChartDir = ./charts/pleme-lib;
            registry = "oci://ghcr.io/pleme-io/charts";
          };

          # Build chart tarballs as Nix packages (for CI caching)
          chartPackages = lib.foldl' (acc: chart: acc // {
            ${chart.name} = pkgs.runCommand "helm-chart-${chart.name}" {
              nativeBuildInputs = [ helm ];
            } ''
              mkdir -p $out build
              cp -r ${chart.chartDir} build/${chart.name}
              cp -r ${./charts/pleme-lib} build/pleme-lib
              chmod -R u+w build
              helm dependency update build/${chart.name}
              helm package build/${chart.name} --destination $out
            '';
          }) {} chartDefs;

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
