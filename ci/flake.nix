# Only used for development & CI
{
  inputs = {
    nixpkgs_unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs_26_05.url = "github:NixOS/nixpkgs/nixos-26.05";

    nix-darwin_unstable.url = "github:nix-darwin/nix-darwin";
    nix-darwin_26_05.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";

    nix-github-actions = {
      url = "github:nix-community/nix-github-actions";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };
  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs_unstable) lib;

      releases = {
        "unstable" = {
          nixpkgs = inputs.nixpkgs_unstable;
          nix-darwin = inputs.nix-darwin_unstable;
          # Nixpkgs 26.11 dropped x86_64-darwin; evaluating it is a hard error.
          systems = [ "aarch64-darwin" ];
        };
        "26.05" = {
          nixpkgs = inputs.nixpkgs_26_05;
          nix-darwin = inputs.nix-darwin_26_05;
          systems = [
            "x86_64-darwin"
            "aarch64-darwin"
          ];
        };
      };

      supportedSystems = lib.unique (lib.concatMap (release: release.systems) (lib.attrValues releases));

      githubPlatforms = {
        "aarch64-darwin" = "macos-26";
        "x86_64-darwin" = "macos-26";
      };

      matrix =
        let
          names = {
            release = builtins.attrNames releases;
            test = builtins.attrNames (
              import ./tests.nix {
                self = null;
                pkgs = null;
                nix-darwin = null;
              }
            );
          };
        in
        lib.pipe names [
          lib.cartesianProduct
          (map (setup: {
            name = "${setup.test}-${setup.release}";
            value = setup;
          }))
          lib.listToAttrs
        ];

      # Unstable doesn't cover every supported system anymore.
      pkgsFor =
        system:
        if lib.elem system releases.unstable.systems then
          inputs.nixpkgs_unstable.legacyPackages.${system}
        else
          inputs.nixpkgs_26_05.legacyPackages.${system};

      forAllSystems = f: lib.genAttrs supportedSystems (system: f (pkgsFor system));

      makeCi =
        { self, brew-src }:
        let
          assembleTest =
            {
              system,
              release,
              test,
            }:
            let
              inputs' = releases.${release};
              pkgs = inputs'.nixpkgs.legacyPackages.${system};
              tests = import ./tests.nix {
                inherit self pkgs;
                inherit (inputs') nix-darwin;
              };
            in
            tests.${test};

          ciTests = lib.genAttrs supportedSystems (
            system:
            lib.mapAttrs (
              name:
              { release, test }:
              assembleTest {
                inherit system release test;
              }
            ) (lib.filterAttrs (name: setup: lib.elem system releases.${setup.release}.systems) matrix)
          );
          ciScripts = lib.mapAttrs (
            system: tests: lib.mapAttrs (name: test: test.config.system.build.ci-script) tests
          ) ciTests;
        in
        {
          inherit ciTests;
          packages = forAllSystems (
            pkgs:
            pkgs.callPackages (self + "/pkgs") {
              inherit brew-src;
            }
          );
          devShell = forAllSystems (
            pkgs:
            pkgs.mkShell {
              nativeBuildInputs = with pkgs; [
                nixfmt
              ];

              BREW_SRC = brew-src;
            }
          );
          githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
            checks = ciScripts;
            platforms = githubPlatforms;
          };
        };
    in
    {
      inherit makeCi;
    };
}
