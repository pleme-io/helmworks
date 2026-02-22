{
  description = "Helmworks: reusable Helm chart library for pleme-io internal services";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      perSystem = { pkgs, lib, ... }:
        let
          helm = pkgs.kubernetes-helm;

          charts = [
            "pleme-microservice"
            "pleme-worker"
            "pleme-web"
            "pleme-cronjob"
            "pleme-migration"
            "pleme-operator"
          ];

          registry = "oci://ghcr.io/pleme-io/charts";

          # Build a chart with dependencies resolved
          buildChart = name: pkgs.runCommand "helm-chart-${name}" {
            nativeBuildInputs = [ helm ];
            src = ./.;
          } ''
            mkdir -p $out build
            cp -r $src/charts/${name} build/${name}
            cp -r $src/charts/pleme-lib build/pleme-lib
            chmod -R u+w build
            helm dependency update build/${name}
            helm package build/${name} --destination $out
          '';

          # Create lint app for a single chart
          mkLintApp = name: pkgs.writeShellApplication {
            name = "lint-${name}";
            runtimeInputs = [ helm ];
            text = ''
              REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
              TMPDIR=$(mktemp -d)
              trap 'rm -rf "$TMPDIR"' EXIT
              cp -r "$REPO_ROOT/charts/${name}" "$TMPDIR/${name}"
              cp -r "$REPO_ROOT/charts/pleme-lib" "$TMPDIR/pleme-lib"
              chmod -R u+w "$TMPDIR"
              helm dependency update "$TMPDIR/${name}"
              echo "=== Linting ${name} ==="
              helm lint "$TMPDIR/${name}"
              echo "=== Template validation ==="
              helm template test "$TMPDIR/${name}" --set image.repository=test 2>/dev/null
              echo "PASS: ${name}"
            '';
          };

          # Create package app for a single chart
          mkPackageApp = name: pkgs.writeShellApplication {
            name = "package-${name}";
            runtimeInputs = [ helm ];
            text = ''
              REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
              OUTPUT_DIR="''${1:-$REPO_ROOT/dist}"
              mkdir -p "$OUTPUT_DIR"
              TMPDIR=$(mktemp -d)
              trap 'rm -rf "$TMPDIR"' EXIT
              cp -r "$REPO_ROOT/charts/${name}" "$TMPDIR/${name}"
              cp -r "$REPO_ROOT/charts/pleme-lib" "$TMPDIR/pleme-lib"
              chmod -R u+w "$TMPDIR"
              helm dependency update "$TMPDIR/${name}"
              helm package "$TMPDIR/${name}" --destination "$OUTPUT_DIR"
              echo "Packaged ${name} → $OUTPUT_DIR"
            '';
          };

          # Create push app for a single chart
          mkPushApp = name: pkgs.writeShellApplication {
            name = "push-${name}";
            runtimeInputs = [ helm ];
            text = ''
              REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
              REGISTRY="''${1:-${registry}}"
              CHART_TGZ=$(find "$REPO_ROOT/dist" -name '${name}-*.tgz' 2>/dev/null | sort -V | tail -1)
              if [ -z "$CHART_TGZ" ]; then
                echo "ERROR: No ${name} tarball in dist/. Run: nix run .#package:${name}"
                exit 1
              fi
              echo "Pushing $CHART_TGZ → $REGISTRY"
              helm push "$CHART_TGZ" "$REGISTRY"
            '';
          };

          # Per-chart apps
          chartApps = lib.foldl' (acc: name: acc // {
            "lint:${name}" = { type = "app"; program = "${mkLintApp name}/bin/lint-${name}"; };
            "package:${name}" = { type = "app"; program = "${mkPackageApp name}/bin/package-${name}"; };
            "push:${name}" = { type = "app"; program = "${mkPushApp name}/bin/push-${name}"; };
          }) {} charts;

          # Per-chart packages
          chartPackages = lib.foldl' (acc: name: acc // {
            ${name} = buildChart name;
          }) {} charts;

        in {
          packages = chartPackages;

          apps = chartApps // {
            # Aggregate apps: lint/package/push/release all charts

            lint = {
              type = "app";
              program = "${pkgs.writeShellApplication {
                name = "lint-all";
                runtimeInputs = [ helm ];
                text = ''
                  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
                  TMPDIR=$(mktemp -d)
                  trap 'rm -rf "$TMPDIR"' EXIT
                  cp -r "$REPO_ROOT/charts/pleme-lib" "$TMPDIR/pleme-lib"
                  FAILED=0
                  for chart in ${lib.concatStringsSep " " charts}; do
                    echo "=== Linting $chart ==="
                    cp -r "$REPO_ROOT/charts/$chart" "$TMPDIR/$chart"
                    chmod -R u+w "$TMPDIR/$chart"
                    helm dependency update "$TMPDIR/$chart" 2>/dev/null
                    if helm lint "$TMPDIR/$chart"; then
                      helm template test "$TMPDIR/$chart" --set image.repository=test 2>/dev/null
                      echo "PASS: $chart"
                    else
                      echo "FAIL: $chart"
                      FAILED=1
                    fi
                  done
                  exit $FAILED
                '';
              }}/bin/lint-all";
            };

            package = {
              type = "app";
              program = "${pkgs.writeShellApplication {
                name = "package-all";
                runtimeInputs = [ helm ];
                text = ''
                  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
                  OUTPUT_DIR="''${1:-$REPO_ROOT/dist}"
                  mkdir -p "$OUTPUT_DIR"
                  for chart in ${lib.concatStringsSep " " charts}; do
                    echo "=== Packaging $chart ==="
                    TMPDIR=$(mktemp -d)
                    cp -r "$REPO_ROOT/charts/$chart" "$TMPDIR/$chart"
                    cp -r "$REPO_ROOT/charts/pleme-lib" "$TMPDIR/pleme-lib"
                    chmod -R u+w "$TMPDIR"
                    helm dependency update "$TMPDIR/$chart" 2>/dev/null
                    helm package "$TMPDIR/$chart" --destination "$OUTPUT_DIR"
                    rm -rf "$TMPDIR"
                  done
                  echo "All charts packaged → $OUTPUT_DIR"
                '';
              }}/bin/package-all";
            };

            push = {
              type = "app";
              program = "${pkgs.writeShellApplication {
                name = "push-all";
                runtimeInputs = [ helm ];
                text = ''
                  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
                  REGISTRY="''${1:-${registry}}"
                  for chart in ${lib.concatStringsSep " " charts}; do
                    CHART_TGZ=$(find "$REPO_ROOT/dist" -name "$chart-*.tgz" 2>/dev/null | sort -V | tail -1)
                    if [ -n "$CHART_TGZ" ]; then
                      echo "=== Pushing $chart ==="
                      helm push "$CHART_TGZ" "$REGISTRY"
                    else
                      echo "SKIP: $chart (no tarball in dist/)"
                    fi
                  done
                '';
              }}/bin/push-all";
            };

            release = {
              type = "app";
              program = "${pkgs.writeShellApplication {
                name = "release-all";
                runtimeInputs = [ helm ];
                text = ''
                  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
                  REGISTRY="''${1:-${registry}}"
                  OUTPUT_DIR="$REPO_ROOT/dist"
                  mkdir -p "$OUTPUT_DIR"
                  TMPBASE=$(mktemp -d)
                  trap 'rm -rf "$TMPBASE"' EXIT
                  cp -r "$REPO_ROOT/charts/pleme-lib" "$TMPBASE/pleme-lib"
                  FAILED=0
                  for chart in ${lib.concatStringsSep " " charts}; do
                    echo ""
                    echo "=========================================="
                    echo "  Releasing $chart"
                    echo "=========================================="
                    cp -r "$REPO_ROOT/charts/$chart" "$TMPBASE/$chart"
                    chmod -R u+w "$TMPBASE/$chart"
                    helm dependency update "$TMPBASE/$chart" 2>/dev/null

                    echo "--- Lint ---"
                    if ! helm lint "$TMPBASE/$chart"; then
                      echo "FAIL: $chart lint"
                      FAILED=1
                      continue
                    fi

                    echo "--- Package ---"
                    helm package "$TMPBASE/$chart" --destination "$OUTPUT_DIR"

                    echo "--- Push ---"
                    CHART_TGZ=$(find "$OUTPUT_DIR" -name "$chart-*.tgz" | sort -V | tail -1)
                    helm push "$CHART_TGZ" "$REGISTRY"
                    echo "DONE: $chart"
                  done
                  exit $FAILED
                '';
              }}/bin/release-all";
            };

            # Template rendering for debugging
            template = {
              type = "app";
              program = "${pkgs.writeShellApplication {
                name = "template";
                runtimeInputs = [ helm ];
                text = ''
                  CHART="''${1:?Usage: nix run .#template -- <chart-name> [values-file]}"
                  VALUES="''${2:-}"
                  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
                  TMPDIR=$(mktemp -d)
                  trap 'rm -rf "$TMPDIR"' EXIT
                  cp -r "$REPO_ROOT/charts/$CHART" "$TMPDIR/$CHART"
                  cp -r "$REPO_ROOT/charts/pleme-lib" "$TMPDIR/pleme-lib"
                  chmod -R u+w "$TMPDIR"
                  helm dependency update "$TMPDIR/$CHART" 2>/dev/null
                  if [ -n "$VALUES" ]; then
                    helm template test "$TMPDIR/$CHART" -f "$VALUES"
                  else
                    helm template test "$TMPDIR/$CHART" --set image.repository=test
                  fi
                '';
              }}/bin/template";
            };
          };

          # Dev shell with helm and related tools
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
