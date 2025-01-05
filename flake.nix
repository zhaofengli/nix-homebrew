{
  description = "Homebrew installation manager for nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    brew-src = {
      url = "github:Homebrew/brew/4.4.5";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nix-darwin, brew-src, ... } @ inputs: let
    # System types to support.
    supportedSystems = [ "x86_64-darwin" "aarch64-darwin" ];

    flakeLock = builtins.fromJSON (builtins.readFile ./flake.lock);
    brewVersion = flakeLock.nodes.brew-src.original.ref;

    forAllSystems =
      function:
      nixpkgs.lib.genAttrs supportedSystems (
        system: function nixpkgs.legacyPackages.${system}
      );
  in {
    packages = forAllSystems (pkgs: pkgs.callPackage ./pkgs {
      inherit inputs;
    });

    devShell = forAllSystems (pkgs: pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
      ];

      BREW_SRC = brew-src;
    });

    ci = forAllSystems (pkgs: import ./ci (inputs // {
      inherit pkgs;
    }));

    darwinModules = {
      nix-homebrew = { lib, ... }: {
        imports = [
          ./modules
        ];
        nix-homebrew.package = lib.mkOptionDefault (brew-src // {
          name = "brew-${brewVersion}";
          version = brewVersion;
        });
      };
    };
  };
}
