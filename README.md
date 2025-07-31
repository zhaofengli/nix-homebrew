# nix-homebrew

`nix-homebrew` manages Homebrew installations on macOS using [nix-darwin](https://github.com/LnL7/nix-darwin).
It pins the Homebrew version and optionally allows for declarative specification of taps.

`nix-homebrew` only installs Homebrew itself and does not manage any package installed by it.
For declarative formula/cask management, use the [`homebrew.*` options](https://daiderd.com/nix-darwin/manual/index.html#opt-homebrew.enable) in nix-darwin which work well in tandem with `nix-homebrew`.


## Quick Start

First of all, you must have [nix-darwin](https://github.com/LnL7/nix-darwin) configured already.
Add the following to your Flake inputs:

```nix
{
  inputs = {
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    # (...)
  };
}
```

### A. New Installation

If you haven't installed Homebrew before, use the following configuration:

```nix
{
  output = { self, nixpkgs, darwin, nix-homebrew, homebrew-core, homebrew-cask, ... }: {
    darwinConfigurations.macbook = {
      # (...)
      modules = [
        nix-homebrew.darwinModules.nix-homebrew
        ({config, ...}: {
          homebrew.taps = builtins.attrNames config.nix-homebrew.taps;
          nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;

            # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
            enableRosetta = true;

            # User owning the Homebrew prefix
            user = "yourname";

            # Optional: Declarative tap management
            taps = {
              "homebrew/homebrew-core" = homebrew-core;
              "homebrew/homebrew-cask" = homebrew-cask;
            };

            # Optional: Enable fully-declarative tap management
            #
            # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
            mutableTaps = false;
          };
        })
      ];
    };
  };
}
```

Once activated, a unified `brew` launcher will be created under `/run/current-system/sw/bin` that automatically selects the correct Homebrew prefix to use based on the architecture.
Run `arch -x86_64 brew` to install X86-64 packages through Rosetta 2.

With `nix-homebrew.mutableTaps = false`, taps can be removed by deleting the corresponding attribute in `nix-homebrew.taps` and activating the new configuration.

Setting `homebrew.taps` to equal `nix-homebrew.taps` attribute names reduces configuration mismatches. 

### B. Existing Homebrew Installation

If you've already installed Homebrew with the official script, you can let `nix-homebrew` automatically migrate it:

```nix
{
  output = { self, darwin, nix-homebrew, ... }: {
    darwinConfigurations.macbook = {
      # (...)
      modules = [
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;

            # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
            enableRosetta = true;

            # User owning the Homebrew prefix
            user = "yourname";

            # Automatically migrate existing Homebrew installations
            autoMigrate = true;
          };
        }
      ];
    };
  };
}
```

## Non-Standard Prefixes

Extra prefixes may be configured:

```nix
{
  nix-homebrew.prefixes = {
    "/some/prefix" = {
      library = "/some/prefix/Library";
      taps = {
        # ...
      };
    };
  };
}
```

Note that with a non-standard prefix, you will no longer be able to use most bottles (prebuilt packages).

## Declarative Taps

In Homebrew, the repo part of all taps always have `homebrew-` prepended.
- https://docs.brew.sh/Taps
- https://docs.brew.sh/Interesting-Taps-and-Forks

`brew tap <user>/<repo>` makes a clone of the repository at `https://github.com/<user>/homebrew-<repo>` into `$(brew --repository)/Library/Taps`.

When declaring taps, please ensure to name the key as a unique folder starting with `homebrew-`, e.g.:
```diff
       nix-homebrew.taps = {
-        "mtslzr/marmaduke-chromium" = inputs.marmaduke-chromium;
+        "mtslzr/homebrew-marmaduke-chromium" = inputs.marmaduke-chromium;
```
The exact GitHub `<user>/<repo>` should almost always work.
