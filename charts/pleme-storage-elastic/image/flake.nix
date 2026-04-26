# pleme-storage-elastic watcher image — Rust binary in distroless OCI.
#
# Build:    nix build .#image
# Push:     nix run .#push   (requires GHCR auth)
# Result:   ghcr.io/pleme-io/pleme-storage-elastic:<version>
#
# Implementation: Rust + kube-rs + reqwest. Compiles to a static-ish
# binary, packaged with cacert in a layered image (~30 MiB total).

{
  description = "pleme-storage-elastic — PVC autosize watcher";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, fenix }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ] (system: let
      pkgs = import nixpkgs { inherit system; };
      version = "0.1.0";

      rustToolchain = fenix.packages.${system}.stable.toolchain;

      rustPlatform = pkgs.makeRustPlatform {
        cargo = rustToolchain;
        rustc = rustToolchain;
      };

      watcher = rustPlatform.buildRustPackage {
        pname   = "pleme-storage-elastic";
        version = version;
        src     = ./.;
        cargoLock = { lockFile = ./Cargo.lock; };

        nativeBuildInputs = with pkgs; [ pkg-config ];
        buildInputs = with pkgs;
          lib.optionals stdenv.isLinux  [ openssl ]
          ++ lib.optionals stdenv.isDarwin [ libiconv darwin.apple_sdk.frameworks.Security ];

        doCheck = true;
        meta = {
          description = "PVC autosize watcher (theory/BREATHABILITY.md §V)";
          license = pkgs.lib.licenses.mit;
          mainProgram = "pleme-storage-elastic";
        };
      };

      # Image only makes sense on Linux. On Darwin the package builds
      # for testing but the image attribute is omitted (dockerTools is
      # Linux-only without cross-compilation setup).
      image = if pkgs.stdenv.isLinux then
        pkgs.dockerTools.buildLayeredImage {
          name = "ghcr.io/pleme-io/pleme-storage-elastic";
          tag  = version;
          contents = with pkgs; [
            watcher
            cacert
            dockerTools.fakeNss
          ];
          config = {
            Entrypoint = [ "${watcher}/bin/pleme-storage-elastic" ];
            User = "65532:65532";
            Env = [
              "PATH=${watcher}/bin"
              "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "RUST_LOG=info,pleme_storage_elastic=debug"
            ];
            Labels = {
              "org.opencontainers.image.source" = "https://github.com/pleme-io/helmworks";
              "org.opencontainers.image.description" =
                "pleme-storage-elastic — PVC autosize watcher (theory/BREATHABILITY.md §V)";
              "org.opencontainers.image.licenses" = "MIT";
              "org.opencontainers.image.version"  = version;
            };
          };
        }
      else
        # On macOS, surface a placeholder that explains why image is
        # absent. This keeps `nix flake check` green from a Mac.
        pkgs.runCommand "pleme-storage-elastic-image-darwin-stub" {} ''
          mkdir -p $out
          echo "Build the OCI image on Linux:" > $out/README
          echo "  nix build .#image --system x86_64-linux" >> $out/README
          echo "  nix build .#image --system aarch64-linux" >> $out/README
        '';

    in {
      packages = {
        default = watcher;
        watcher = watcher;
        image   = image;
      };

      apps.default = { type = "app"; program = "${watcher}/bin/pleme-storage-elastic"; };

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = (with pkgs; [ rustToolchain pkg-config skopeo kubectl ])
          ++ pkgs.lib.optionals pkgs.stdenv.isLinux  [ pkgs.openssl ]
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
               pkgs.libiconv pkgs.darwin.apple_sdk.frameworks.Security ];
      };
    });
}
