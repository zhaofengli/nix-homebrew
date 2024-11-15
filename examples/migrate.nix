# Migrate from an existing Homebrew installation

{ pkgs, ... }:
{
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    autoMigrate = true;
    user = "yourname";
  };
}
