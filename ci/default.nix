# Activates example configurations on CI

{ self, pkgs, nix-darwin, ... }:

let
  inherit (pkgs) lib system;
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
