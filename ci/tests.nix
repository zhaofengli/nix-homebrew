{
  self,
  pkgs,
  nix-darwin,
}:

let
  inherit (pkgs) lib system;

  tools = self.packages.${pkgs.system};

  makeTest =
    module:
    nix-darwin.lib.darwinSystem {
      inherit system pkgs;
      modules = [
        self.darwinModules.nix-homebrew
        module
        (
          {
            pkgs,
            lib,
            config,
            ...
          }:
          {
            options = {
              ci = {
                preScript = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                };
                script = lib.mkOption {
                  type = lib.types.lines;
                  default = ''
                    sudo rm -f /etc/bashrc /etc/nix/nix.conf /etc/nix/nix.custom.conf
                    sudo "${config.system.build.toplevel}/activate"
                    export PATH=/run/current-system/sw/bin:$PATH
                  '';
                };
                postScript = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                };
              };
            };
            config = {
              documentation.enable = false;
              system.stateVersion = 6;
              nix-homebrew = {
                user = lib.mkForce "runner";
              };

              system.build.ci-script = pkgs.writeShellScript "ci-script.sh" ''
                set -euo pipefail
                if [[ -z "''${NIX_HOMEBREW_CI:-}" ]]; then
                  >&2 echo "This script can only be run on nix-homebrew CI."
                  exit 1
                fi
                set -x
                ${config.ci.preScript}
                ${config.ci.script}
                ${config.ci.postScript}
              '';
            };
          }
        )
      ];
    };

  makeTapValidationTest =
    module:
    makeTest (
      { pkgs, config, ... }:
      let
        prefixName =
          if pkgs.stdenv.hostPlatform.isAarch64 then
            config.nix-homebrew.defaultArm64Prefix
          else
            config.nix-homebrew.defaultIntelPrefix;
        library = config.nix-homebrew.prefixes.${prefixName}.library;
        fakeCaskTap = pkgs.runCommandLocal "homebrew-cask-test-tap" { } ''
          mkdir -p "$out/Casks/u"
          touch "$out/Casks/u/ungoogled-chromium.rb"
        '';
      in
      {
        imports = [
          module
        ];

        _module.args.library = library;

        nix-homebrew = {
          enable = true;
          autoMigrate = true;
          taps = {
            "homebrew/homebrew-cask" = fakeCaskTap;
          };
        };

        ci.preScript = ''
          >&2 echo "Removing runner Homebrew taps before declarative tap validation"
          if [[ -e "${library}/Taps" || -L "${library}/Taps" ]]; then
            sudo rm -rf "${library}/Taps"
          fi
        '';

        ci.postScript = ''
          >&2 echo "Checking declarative cask tap realpaths"
          tap_root="${library}/Taps"
          cask_path="$tap_root/homebrew/homebrew-cask/Casks/u/ungoogled-chromium.rb"

          test -f "$cask_path"

          tap_root_real="$(${pkgs.coreutils}/bin/realpath "$tap_root")"
          cask_real="$(${pkgs.coreutils}/bin/realpath "$cask_path")"

          case "$cask_real" in
            "$tap_root_real"/*) ;;
            *)
              >&2 echo "Expected cask realpath to stay under managed Taps root"
              >&2 echo "Taps realpath: $tap_root_real"
              >&2 echo "Cask realpath: $cask_real"
              exit 1
              ;;
          esac
        '';
      }
    );
in
{
  migrate = makeTest (
    { pkgs, config, ... }:
    {
      imports = [
        (self + "/examples/migrate.nix")
      ];
      nix-homebrew.enableRosetta = lib.mkForce pkgs.stdenv.hostPlatform.isAarch64;

      # We only have Apple Silicon instances - Only test the install steps on native
      # Apple Silicon for now
      ci.preScript = lib.optionalString pkgs.stdenv.hostPlatform.isAarch64 ''
        >&2 echo "Installing some package with Homebrew"
        brew install unbound

        >&2 echo "Adding a third-party tap imperatively"
        brew tap koekeishiya/formulae
      '';
      ci.postScript = ''
        >&2 echo "Checking brew"
        which brew
      ''
      + lib.optionalString pkgs.stdenv.hostPlatform.isAarch64 ''
        >&2 echo "Checking that we can still use the unbound package"
        $(brew --prefix)/sbin/unbound -V

        >&2 echo "Checking that we can still use the tap we added imperatively"
        brew install koekeishiya/formulae/yabai
      ''
      + lib.optionalString config.nix-homebrew.enableRosetta ''
        >&2 echo "Checking we can execute the Intel brew with arch -x86_64"
        arch -x86_64 /usr/local/bin/brew config | grep "HOMEBREW_PREFIX: /usr/local"

        >&2 echo "Checking that the unified brew launcher selects the correct prefix"
        arch -arm64 brew config | grep "HOMEBREW_PREFIX: /opt/homebrew"
        arch -x86_64 brew config | grep "HOMEBREW_PREFIX: /usr/local"
      '';
    }
  );

  tap-validation-mutable = makeTapValidationTest { };

  tap-validation-declarative = makeTapValidationTest (
    { library, ... }:
    {
      nix-homebrew.mutableTaps = false;

      ci.preScript = ''
        >&2 echo "Removing runner Homebrew taps before declarative tap validation"
        if [[ -e "${library}/Taps" || -L "${library}/Taps" ]]; then
          sudo rm -rf "${library}/Taps"
        fi
      '';
    }
  );

  nuke-homebrew-repository = makeTest {
    ci.script = lib.mkForce ''
      cat "${tools.nuke-homebrew-repository.passthru.tests.test-nuke}"
    '';
  };
}
