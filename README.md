# nix-bundle-logos-module-install

A [Nix bundler](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-bundle.html) that packages a module derivation into an `.lgx` file and installs it via `lgpm`. Combines [nix-bundle-lgx](https://github.com/logos-co/nix-bundle-lgx) (LGX packaging) and [lgpm](https://github.com/logos-co/logos-package-manager) (installation) into a single step.

## Bundlers

### `#default` / `#dev`

Bundles the derivation's `lib/` directory into a **dev-variant** `.lgx` package (libraries resolve from `/nix/store` at runtime), then installs it via `lgpm`. Suitable for development environments where the Nix store is available.

```bash
nix bundle --bundler github:logos-co/nix-bundle-logos-module-install#dev github:logos-co/logos-accounts-module#lib
```

### `#portable`

First passes the derivation through `nix-bundle-dir` to create a self-contained directory with relocated rpaths, bundles it into a **portable-variant** `.lgx` package, then installs it via `lgpm`. Suitable for distribution without Nix store dependency.

```bash
nix bundle --bundler github:logos-co/nix-bundle-logos-module-install#portable github:logos-co/logos-accounts-module#lib
```

## Output

The bundler produces an installed module directory structure in `$out/`:

```
$out/
  modules/           # Core modules (type: "core")
    my_module/
      libmy_module_plugin.dylib
      manifest.json
      variant
  plugins/           # UI plugins (type: "ui", "ui_qml")
    my_ui_plugin/
      libmy_ui_plugin.dylib
      manifest.json
      variant
```

Module type is determined from `metadata.json` — core modules are installed to `modules/`, UI plugins to `plugins/`.

## Expected derivation layout

Same as [nix-bundle-lgx](https://github.com/logos-co/nix-bundle-lgx) — the input derivation must expose a `lib/` subdirectory containing the shared library:

```
$out/
  lib/
    libfoo.dylib   # or libfoo.so
  metadata.json    # optional
```

## Programmatic use

The bundlers can be used as functions in other flakes:

```nix
{
  inputs.nix-bundle-logos-module-install.url = "github:logos-co/nix-bundle-logos-module-install";

  outputs = { nix-bundle-logos-module-install, ... }:
    let
      installDev = nix-bundle-logos-module-install.bundlers.${system}.dev;
      installPortable = nix-bundle-logos-module-install.bundlers.${system}.portable;

      # Each returns a derivation with modules/ and/or plugins/ subdirectories
      myModuleInstalled = installDev myModuleLib;
      myModuleInstalledPortable = installPortable myModuleLib;
    in { ... };
}
```

## Modules built with logos-module-builder

Modules built with `logos-module-builder` automatically get `#install` and `#install-portable` package outputs that use this bundler:

```bash
nix build github:logos-co/logos-accounts-module#install
nix build github:logos-co/logos-accounts-module#install-portable
```
