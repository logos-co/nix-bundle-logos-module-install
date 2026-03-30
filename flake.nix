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
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
        bundleLgxDev = nix-bundle-lgx.bundlers.${system}.default;
        bundleLgxPortable = nix-bundle-lgx.bundlers.${system}.portable;
        lgpmCli = logos-package-manager.packages.${system}.cli;
        lgpmCliPortable = logos-package-manager.packages.${system}.cli-portable;
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
            in pkgs.runCommand "${name}-install" {
              nativeBuildInputs = [ lgpm ];
            } ''
              mkdir -p $out/modules $out/plugins

              for lgxFile in ${lgxPkg}/*.lgx; do
                echo "Installing $(basename "$lgxFile") via lgpm..."
                lgpm --modules-dir "$out/modules" --ui-plugins-dir "$out/plugins" install --file "$lgxFile"
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
