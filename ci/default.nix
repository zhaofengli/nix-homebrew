# Activates example configurations on CI

{ self, pkgs, nix-darwin, ... }:

let
  inherit (pkgs) lib system;
  checkCIMarker = ''
    if [[ ! -e /etc/nix-homebrew-ci ]]; then
      >&2 echo "[!!] This configuration is only intended for nix-homebrew CI"
      >&2 echo "[!!] Refusing to activate since it will likely brick your machine"
      exit 1
    fi
  '';
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

        system.activationScripts.preActivation.text = lib.mkBefore checkCIMarker;
        system.activationScripts.preUserActivation.text = lib.mkBefore checkCIMarker;
      }
    ];
  };
in {
  migrate = makeProfile "migrate";
}
