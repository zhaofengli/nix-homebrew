{ callPackage, brew-src ? null }:
{
  nuke-homebrew-repository = callPackage ./nuke-homebrew-repository {
    inherit brew-src;
  };
}
