# Migrate from an existing Homebrew installation

{ pkgs, ... }:
{
  nix-homebrew = {
    enable = true;
    autoMigrate = true;
    user = "yourname";
  };
}
