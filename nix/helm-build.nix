{ pkgs }:
let
  helm = pkgs.kubernetes-helm;
  helmUnittest = pkgs.kubernetes-helm-unittest or null;
in
{
  # Package a chart directory into a .tgz tarball
  mkHelmChart = { name, chartDir, version ? null }:
    pkgs.runCommand "helm-chart-${name}" {
      nativeBuildInputs = [ helm ];
    } ''
      mkdir -p $out
      ${if version != null then ''
        # Update chart version if specified
        sed -i 's/^version:.*/version: ${version}/' ${chartDir}/Chart.yaml
      '' else ""}
      # Update dependencies (resolves file:// references)
      helm dependency update ${chartDir} 2>/dev/null || true
      helm package ${chartDir} --destination $out
    '';

  # Nix app that pushes a packaged chart to OCI registry
  mkHelmPushApp = { name, chartPackage, registry ? "oci://ghcr.io/pleme-io/charts" }:
    pkgs.writeShellApplication {
      name = "helm-push-${name}";
      runtimeInputs = [ helm ];
      text = ''
        CHART_TGZ=$(find ${chartPackage} -name '*.tgz' | head -1)
        if [ -z "$CHART_TGZ" ]; then
          echo "ERROR: No chart tarball found in ${chartPackage}"
          exit 1
        fi
        echo "Pushing $CHART_TGZ to ${registry}"
        helm push "$CHART_TGZ" "${registry}"
      '';
    };

  # Nix check that runs helm lint + helm template
  mkHelmLintCheck = { name, chartDir }:
    pkgs.runCommand "helm-lint-${name}" {
      nativeBuildInputs = [ helm ];
    } ''
      # Update dependencies first
      cp -r ${chartDir} ./chart
      chmod -R u+w ./chart
      helm dependency update ./chart 2>/dev/null || true
      echo "=== Linting ${name} ==="
      helm lint ./chart
      echo "=== Template rendering ${name} ==="
      helm template test ./chart 2>/dev/null || helm template test ./chart --set image.repository=test
      echo "PASS" > $out
    '';

  # Nix check that runs helm unittest
  mkHelmTestCheck = { name, chartDir, testDir }:
    pkgs.runCommand "helm-test-${name}" {
      nativeBuildInputs = [ helm ] ++ (if helmUnittest != null then [ helmUnittest ] else []);
    } ''
      if ! command -v helm-unittest &>/dev/null && ! helm plugin list | grep -q unittest; then
        echo "SKIP: helm-unittest not available"
        echo "SKIP" > $out
        exit 0
      fi
      cp -r ${chartDir} ./chart
      chmod -R u+w ./chart
      helm dependency update ./chart 2>/dev/null || true
      cp -r ${testDir} ./chart/tests
      helm unittest ./chart
      echo "PASS" > $out
    '';

  # Complete SDLC: lint, test, package, push
  mkHelmSdlcApps = { name, chartDir, testDir ? null, version ? null, registry ? "oci://ghcr.io/pleme-io/charts" }:
    let
      chart = pkgs.runCommand "helm-chart-${name}" {
        nativeBuildInputs = [ helm ];
      } ''
        mkdir -p $out
        cp -r ${chartDir} ./chart
        chmod -R u+w ./chart
        ${if version != null then ''
          sed -i 's/^version:.*/version: ${version}/' ./chart/Chart.yaml
        '' else ""}
        helm dependency update ./chart 2>/dev/null || true
        helm package ./chart --destination $out
      '';
    in {
      lint = pkgs.writeShellApplication {
        name = "helm-lint-${name}";
        runtimeInputs = [ helm ];
        text = ''
          CHART_DIR="''${1:-charts/${name}}"
          cp -r "$CHART_DIR" /tmp/chart-lint
          chmod -R u+w /tmp/chart-lint
          helm dependency update /tmp/chart-lint 2>/dev/null || true
          helm lint /tmp/chart-lint
          helm template test /tmp/chart-lint --set image.repository=test 2>/dev/null
          echo "Lint passed for ${name}"
          rm -rf /tmp/chart-lint
        '';
      };

      package = pkgs.writeShellApplication {
        name = "helm-package-${name}";
        runtimeInputs = [ helm ];
        text = ''
          CHART_DIR="''${1:-charts/${name}}"
          OUTPUT_DIR="''${2:-dist}"
          mkdir -p "$OUTPUT_DIR"
          cp -r "$CHART_DIR" /tmp/chart-pkg
          chmod -R u+w /tmp/chart-pkg
          helm dependency update /tmp/chart-pkg 2>/dev/null || true
          helm package /tmp/chart-pkg --destination "$OUTPUT_DIR"
          echo "Packaged ${name} to $OUTPUT_DIR"
          rm -rf /tmp/chart-pkg
        '';
      };

      push = pkgs.writeShellApplication {
        name = "helm-push-${name}";
        runtimeInputs = [ helm ];
        text = ''
          CHART_TGZ="''${1:-$(find dist -name '${name}-*.tgz' | head -1)}"
          REGISTRY="''${2:-${registry}}"
          if [ -z "$CHART_TGZ" ]; then
            echo "ERROR: No chart tarball found. Run package first."
            exit 1
          fi
          echo "Pushing $CHART_TGZ to $REGISTRY"
          helm push "$CHART_TGZ" "$REGISTRY"
        '';
      };

      release = pkgs.writeShellApplication {
        name = "helm-release-${name}";
        runtimeInputs = [ helm ];
        text = ''
          CHART_DIR="''${1:-charts/${name}}"
          REGISTRY="''${2:-${registry}}"
          OUTPUT_DIR="dist"
          mkdir -p "$OUTPUT_DIR"

          echo "=== Linting ==="
          cp -r "$CHART_DIR" /tmp/chart-release
          chmod -R u+w /tmp/chart-release
          helm dependency update /tmp/chart-release 2>/dev/null || true
          helm lint /tmp/chart-release

          echo "=== Packaging ==="
          helm package /tmp/chart-release --destination "$OUTPUT_DIR"

          echo "=== Pushing ==="
          CHART_TGZ=$(find "$OUTPUT_DIR" -name '${name}-*.tgz' | sort -V | tail -1)
          helm push "$CHART_TGZ" "$REGISTRY"

          echo "=== Released ${name} ==="
          rm -rf /tmp/chart-release
        '';
      };
    };
}
