# Use a non-standard prefix

{ pkgs, ... }:
{
  nix-homebrew = {
    enable = true;
    prefixes = {
      "/usr/local".enable = true;
      "/opt/homebrew".enable = true;
      "/opt/nix-homebrew" = {
        enable = true;
        library = "/opt/nix-homebrew/Library";
      };
    };
    user = "yourname";
    defaultIntelPrefix = "/opt/nix-homebrew";
    defaultArm64Prefix = "/opt/nix-homebrew";
  };
}
