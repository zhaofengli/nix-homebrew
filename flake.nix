{
  description = "Homebrew installation manager for nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    flake-utils.url = "github:numtide/flake-utils";
    brew-src = {
      url = "github:Homebrew/brew/4.3.1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nix-darwin, flake-utils, brew-src, ... } @ inputs: let
    # System types to support.
    supportedSystems = [ "x86_64-darwin" "aarch64-darwin" ];

    flakeLock = builtins.fromJSON (builtins.readFile ./flake.lock);
    brewVersion = flakeLock.nodes.brew-src.original.ref;
  in flake-utils.lib.eachSystem supportedSystems (system: let
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages = pkgs.callPackage ./pkgs {
      inherit inputs;
    };
    devShell = pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
      ];

      BREW_SRC = brew-src;
    };
  }) // {
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
    darwinConfigurations = {
      ci = import ./ci inputs;
    };
  };
}
