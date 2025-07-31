{
  description = "Homebrew installation manager for nix-darwin";

  inputs = {
    brew-src = {
      url = "github:Homebrew/brew/4.5.9";
      flake = false;
    };
  };

  outputs = { self, brew-src }: let
    flakeLock = builtins.fromJSON (builtins.readFile ./flake.lock);
    brewVersion = flakeLock.nodes.brew-src.original.ref;

    ci = (import ./ci/flake-compat.nix).makeCi {
      inherit self brew-src;
    };
  in {
    darwinModules = rec {
      nix-homebrew = { lib, ... }: {
        imports = [
          ./modules
        ];
        nix-homebrew.package = lib.mkOptionDefault (brew-src // {
          name = "brew-${brewVersion}";
          version = brewVersion;
        });
      };

      default = nix-homebrew;
    };

    inherit (ci) packages devShell ciTests githubActions;
  };
}
