# Activates example configurations on CI

{ self, nix-darwin, nixpkgs, ... }:

let
  system = builtins.fromJSON (builtins.readFile ./system.json);
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;
  makeProfile = example: nix-darwin.lib.darwinSystem {
    inherit system pkgs;
    modules = [
      self.darwinModules.nix-homebrew
      (../examples + "/${example}.nix")
      {
        documentation.enable = false;
        services.nix-daemon.enable = true;
        nix-homebrew = {
          user = lib.mkForce "runner";
        };
      }
    ];
  };
in {
  migrate = makeProfile "migrate";
}
