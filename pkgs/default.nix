{ callPackage, inputs ? {} }:
{
  nuke-homebrew-repository = callPackage ./nuke-homebrew-repository {
    inherit inputs;
  };
}
