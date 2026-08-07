{
  description = "Nix bundler that packages module derivations into LGX and installs them via lgpm";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    nixpkgs.follows = "logos-nix/nixpkgs";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    logos-package-manager.url = "github:logos-co/logos-package-manager";
  };

  outputs = { self, nixpkgs, logos-nix, nix-bundle-lgx, logos-package-manager }:
    let
      # lgpm RUNS during the build to install the .lgx, so on a cross target it
      # comes from the build system. The .lgx bundler is keyed by the TARGET on
      # purpose: it decides the variant name and the library extension from its
      # own pkgs, so keying it by the build system would label a Windows package
      # "linux-amd64" and look for a .so payload that is actually a .dll.
      buildSystemFor = target:
        if target == "x86_64-windows" then "x86_64-linux" else target;

      forAllSystems = f: logos-nix.lib.forAllTargets ({ system, pkgs }:
        let buildSystem = buildSystemFor system; in f {
          inherit system pkgs;
          bundleLgxDev = nix-bundle-lgx.bundlers.${system}.default;
          bundleLgxPortable = nix-bundle-lgx.bundlers.${system}.portable;
          lgpmCli = logos-package-manager.packages.${buildSystem}.cli;
          lgpmCliPortable = logos-package-manager.packages.${buildSystem}.cli-portable;
        });
    in
    {
      bundlers = forAllSystems ({ pkgs, bundleLgxDev, bundleLgxPortable, lgpmCli, lgpmCliPortable, ... }:
        let
          # Build an LGX package from the derivation, then install it via lgpm.
          # Output: $out/modules/<name>/... and/or $out/plugins/<name>/...
          mkInstallBundle = { bundleLgx, lgpm }: drv:
            let
              lgxPkg = bundleLgx drv;
              name = drv.pname or drv.name or "module";
              # Cross only: lgpm runs on the builder, so on a cross target it
              # must be told which platform it is laying out. Left EMPTY when
              # target == build, so the fail-closed check still protects normal
              # builds -- it is what stops a Windows package being installed as
              # a Linux one, and it should never be bypassed by default.
              # Nix doubles are <arch>-<os>; lgpm variants are <os>-<arch> and
              # do not always use the same arch spelling, so translate rather
              # than pass the system through. Unknown targets throw: a wrong
              # variant name would be rejected far from here, and silently
              # guessing is exactly what the fail-closed check exists to stop.
              lgpmVariantFor = nixSystem: {
                "x86_64-windows" = "windows-x86_64";
                "aarch64-windows" = "windows-arm64";
                "x86_64-linux" = "linux-x86_64";
                "aarch64-linux" = "linux-arm64";
                "x86_64-darwin" = "darwin-x86_64";
                "aarch64-darwin" = "darwin-arm64";
              }.${nixSystem} or (throw
                "nix-bundle-logos-module-install: no lgpm variant name known for ${nixSystem}");

              platformFlag = pkgs.lib.optionalString
                (pkgs.stdenv.hostPlatform.system != pkgs.stdenv.buildPlatform.system)
                "--platform ${lgpmVariantFor pkgs.stdenv.hostPlatform.system}";
            in pkgs.pkgsBuildBuild.runCommand "${name}-install" {
              nativeBuildInputs = [ lgpm ];
            } ''
              mkdir -p $out/modules $out/plugins

              for lgxFile in ${lgxPkg}/*.lgx; do
                echo "Installing $(basename "$lgxFile") via lgpm..."
                lgpm ${platformFlag} --modules-dir "$out/modules" --ui-plugins-dir "$out/plugins" install --file "$lgxFile"
              done
            '';
        in {
          # Dev install: raw nix output with -dev variant (requires /nix/store at runtime)
          default = mkInstallBundle { bundleLgx = bundleLgxDev; lgpm = lgpmCli; };
          dev = mkInstallBundle { bundleLgx = bundleLgxDev; lgpm = lgpmCli; };

          # Portable install: self-contained bundle (no /nix/store dependency)
          portable = mkInstallBundle { bundleLgx = bundleLgxPortable; lgpm = lgpmCliPortable; };
        }
      );
    };
}
