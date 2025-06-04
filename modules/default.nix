# Homebrew installation manager
#
# By default, we use the same prefixes as upstream for compatbility
# with bottles (prebuilt packages) as well as existing installations
# done by the official script. Adding and updating taps imperatively
# will continue to work - Declarative tap management is optional.
#
# During activation, we create `$HOMEBREW_PREFIX` as well as the
# regular sub-directories (Cellar, Caskroom, etc.) if they don't
# exist already. Where we deviate from upstream is that we synthesize
# `$HOMEBREW_LIBRARY`:
#
# - `Library`:
#   - `Taps`: Optionally managed by nix-darwin
#   - `Homebrew`: Symlink to Homebrew code inside the Nix store
#
# This avoids the problem in the official layout where state is mixed
# with code inside `$HOMEBREW_REPOSITORY`.
#
# On Apple Silicon, since a separate prefix is required for Intel
# (Rosetta 2), we provide a unified `brew` launcher (`brewLauncher`)
# that automatically selects the correct prefix based on the architecture.
# Use `arch -x86_64 brew` to install X86-64 packages.

{ pkgs, lib, config, options, ... }:
let
  inherit (lib) types;

  # When this file exists under $HOMEBREW_PREFIX or a specific
  # tap, it means it's managed by us.
  nixMarker = ".managed_by_nix_darwin";

  cfg = config.nix-homebrew;

  tools = pkgs.callPackage ../pkgs { };

  brew = if cfg.patchBrew then patchBrew cfg.package else cfg.package;
  ruby = pkgs.ruby_3_4;

  # Sadly, we cannot replace coreutils since the GNU implementations
  # behave differently.
  runtimePath = lib.makeBinPath [ pkgs.gitMinimal ];

  prefixType = types.submodule ({ name, ... }: {
    options = {
      enable = lib.mkOption {
        description = ''
          Whether to set up this Homebrew prefix.
        '';
      };
      prefix = lib.mkOption {
        description = ''
          The Homebrew prefix.

          By default, it's `/opt/homebrew` for Apple Silicon Macs and
          `/usr/local` for Intel Macs.
        '';
        type = types.str;
        default = name;
      };
      library = lib.mkOption {
        description = ''
          The Homebrew library.

          By default, it's `/opt/homebrew/Library` for Apple Silicon Macs and
          `/usr/local/Homebrew/Library` for Intel Macs.
        '';
        type = types.str;
      };
      taps = lib.mkOption {
        description = ''
          A set of Nix-managed taps.
        '';
        type = types.attrsOf types.package;
        default = {};
        example = lib.literalExpression ''
          {
            "homebrew/homebrew-core" = pkgs.fetchFromGitHub {
              owner = "homebrew";
              repo = "homebrew-core";
              rev = "...";
              hash = "...";
            };
          }
        '';
      };
    };
  });

  # Our unified brew launcher script.
  #
  # We use `/bin/bash` (Bash 3.2 :/) instead of `${runtimeShell}`
  # for compatibility with `arch -x86_64`.
  brewLauncher = pkgs.writeScriptBin "brew" (''
    #!/bin/bash
    set -euo pipefail
    cur_arch=$(/usr/bin/uname -m)
  '' + lib.optionalString (cfg.prefixes.${cfg.defaultArm64Prefix}.enable) ''
    if [[ "$cur_arch" == "arm64" ]]; then
      exec "${cfg.prefixes.${cfg.defaultArm64Prefix}.prefix}/bin/brew" "$@"
    fi
  '' + lib.optionalString (cfg.prefixes.${cfg.defaultIntelPrefix}.enable) ''
    if [[ "$cur_arch" == "x86_64" ]]; then
      exec "${cfg.prefixes.${cfg.defaultIntelPrefix}.prefix}/bin/brew" "$@"
    fi
  '' + ''
    >&2 echo "nix-homebrew: No Homebrew installation available for $cur_arch"
    exit 1
  '');

  # Prefix-specific bin/brew
  #
  # No prefix/library/repo auto-detection, everything is configured by Nix.
  makeBinBrew = prefix: let
    template = pkgs.writeText "brew.in" (''
      #!/bin/bash
      export HOMEBREW_PREFIX="@prefix@"
      export HOMEBREW_LIBRARY="@library@"
      export HOMEBREW_REPOSITORY="$HOMEBREW_LIBRARY/.homebrew-is-managed-by-nix"
      export HOMEBREW_BREW_FILE="@out@"

      # Homebrew itself cannot self-update, so we set
      # fake before/after versions to make `update-report.rb` happy
      export HOMEBREW_UPDATE_BEFORE="nix"
      export HOMEBREW_UPDATE_AFTER="nix"
    '' + lib.optionalString (!cfg.mutableTaps) ''
      # Disable auto-update since everything is pinned
      export HOMEBREW_NO_AUTO_UPDATE=1
    '' + lib.optionalString (prefix.taps ? "homebrew/homebrew-core") ''
      # Disable API to use pinned homebrew-core
      export HOMEBREW_NO_INSTALL_FROM_API=1
    '' + (lib.optionalString (cfg.extraEnv != {})
            (lib.concatLines (lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cfg.extraEnv)))
       + (builtins.readFile ./brew.tail.sh));
  in pkgs.replaceVarsWith {
    name = "brew";
    src = template;
    isExecutable = true;

    # Must retain #!/bin/bash, otherwise `arch -x86_64 /usr/local/bin/brew`
    # on Apple Silicon will not work.
    dontPatchShebangs = true;

    replacements = {
      out = placeholder "out";
      inherit runtimePath;
      inherit (prefix) prefix library;
    };
  };

  setupHomebrew = let
    enabledPrefixes = lib.filter (prefix: prefix.enable) (builtins.attrValues cfg.prefixes);
  in pkgs.writeShellScript "setup-homebrew" ''
    set -euo pipefail
    source ${./utils.sh}

    NIX_HOMEBREW_UID=$(id -u "${cfg.user}" || (error "Failed to get UID of ${cfg.user}"; exit 1))
    NIX_HOMEBREW_GID=$(dscl . -read "/Groups/${cfg.group}" | awk '($1 == "PrimaryGroupID:") { print $2 }' || (error "Failed to get GID of ${cfg.group}"; exit 1))

    is_in_nix_store() {
      # /nix/store/anything -> inside
      # /nix/store/.../link-to-outside-store -> inside
      # ./result-link-into-store -> inside

      [[ "$1" != "${builtins.storeDir}"* ]] || return 0

      if [[ -e "$1" ]]
      then
        path="$(readlink -f $1)"
      else
        path="$1"
      fi

      if [[ "$path" == "${builtins.storeDir}"* ]]
      then
        return 0
      else
        return 1
      fi
    }

    is_occupied() {
      [[ -e "$1" ]] && ([[ ! -L "$1" ]] || ! is_in_nix_store "$1")
    }

    ${lib.concatMapStrings setupPrefix enabledPrefixes}

    if test -n "${toString cfg.enableRosetta}" && ! pgrep -q oahd; then
      warn "The Intel Homebrew prefix has been set up, but Rosetta isn't installed yet."
      ohai "Run ''${tty_bold}softwareupdate --install-rosetta''${tty_reset} to install it."
    fi
  '';

  setupPrefix = prefix: ''
    HOMEBREW_PREFIX="${prefix.prefix}"
    HOMEBREW_LIBRARY="${prefix.library}"

    >&2 echo "setting up Homebrew ($HOMEBREW_PREFIX)..."

    HOMEBREW_CODE="$HOMEBREW_LIBRARY/Homebrew"
    if is_occupied "$HOMEBREW_CODE"; then
      # Probably an existing installation
      warn "An existing $HOMEBREW_CODE is in the way"
      warn "$HOMEBREW_PREFIX seems to contain an existing copy of Homebrew."

      if [[ -e "$HOMEBREW_PREFIX/.git" ]]; then
        # Looks like an Apple Silicon installation
        ohai "Looks like an Apple Silicon installation (Homebrew prefix is the repository)"
        HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX"
      elif [[ -e "$HOMEBREW_PREFIX/Homebrew/.git" ]]; then
        # Looks like an Intel installation
        ohai "Looks like an Intel installation (Homebrew repository is under the 'Homebrew' subdirectory)"
        HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
      else
        # Custom installation?
        ohai "Please uninstall Homebrew and try activating again."
        exit 1
      fi

      if [[ -z "${toString cfg.autoMigrate}" ]]; then
        ohai "There are two ways to proceed:"
        ohai "1. Use the official uninstallation script to remove Homebrew (you will lose all taps and installed packages)"
        ohai "2. Set nix-homebrew.autoMigrate = true; to allow nix-homebrew to migrate the installation"

        ohai "During auto-migration, nix-homebrew will delete the existing installation while keeping installed packages."
        exit 1
      fi

      ohai "Attempting to migrate Homebrew installation..."
      ${tools.nuke-homebrew-repository} "$HOMEBREW_REPOSITORY"
    fi

    if [[ ! -e "$HOMEBREW_PREFIX/${nixMarker}" ]]; then
      initialize_prefix
    fi

    # Synthetize $HOMEBREW_LIBRARY
    /bin/ln -shf "${brew}/Library/Homebrew" "$HOMEBREW_LIBRARY/Homebrew"
    ${setupTaps prefix.taps}

    # Make a fake $HOMEBREW_REPOSITORY
    rm -rf "$HOMEBREW_LIBRARY/.homebrew-is-managed-by-nix"
    "''${MKDIR[@]}" "$HOMEBREW_LIBRARY/.homebrew-is-managed-by-nix/.git"
    "''${CHOWN[@]}" "$NIX_HOMEBREW_UID:$NIX_HOMEBREW_GID" "$HOMEBREW_LIBRARY/.homebrew-is-managed-by-nix"
    "''${CHMOD[@]}" 775 "$HOMEBREW_LIBRARY/.homebrew-is-managed-by-nix/"{,.git}
    "''${TOUCH[@]}" "$HOMEBREW_LIBRARY/.homebrew-is-managed-by-nix/.git/HEAD"

    # Link generated bin/brew
    BIN_BREW="$HOMEBREW_PREFIX/bin/brew"
    if is_occupied "$BIN_BREW"; then
      error "An existing $BIN_BREW is in the way"
      exit 1
    fi
    /bin/ln -shf "${makeBinBrew prefix}" "$BIN_BREW"
  '';

  setupTaps = taps:
    # Mixed taps
    if cfg.mutableTaps then lib.concatMapStrings (path: let
      # Each path must be in the form of `user/repo`
      namespace = builtins.head (lib.splitString "/" path);
      target = taps.${path};

      namespaceDir = "$HOMEBREW_LIBRARY/Taps/${namespace}";
      tapDir = "$HOMEBREW_LIBRARY/Taps/${path}";
    in ''
      if [[ -e "${namespaceDir}" ]] && [[ ! -d "${namespaceDir}" ]]; then
        error "$tty_underline${namespaceDir}$tty_reset is in the way and needs to be moved out for $tty_underline${path}$tty_reset"
        exit 1
      fi
      if is_occupied "${tapDir}"; then
        error "An existing $tty_underline${tapDir}$tty_reset is in the way"
        exit 1
      fi
      "''${MKDIR[@]}" "${namespaceDir}"
      "''${CHOWN[@]}" "$NIX_HOMEBREW_UID:$NIX_HOMEBREW_GID" "${namespaceDir}"
      "''${CHMOD[@]}" "ug=rwx" "${namespaceDir}"
      /bin/ln -shf "${target}" "${tapDir}"
    '') (builtins.attrNames taps)

    # Fully declarative taps
    else let
      env = pkgs.runCommandLocal "taps-env" {} (lib.concatMapStrings (path: let
        namespace = builtins.head (lib.splitString "/" path);
        target = taps.${path};
      in ''
        mkdir -p "$out/${namespace}"
        ln -s "${target}" "$out/${path}"
      '') (builtins.attrNames taps));
    in ''
      if is_occupied "$HOMEBREW_LIBRARY/Taps"; then
        error "An existing $tty_underline$HOMEBREW_LIBRARY/Taps$tty_reset is in the way"
        exit 1
      fi

      /bin/ln -shf "${env}" "$HOMEBREW_LIBRARY/Taps"
    '';

  patchBrew = brew: pkgs.runCommandLocal "${brew.name or "brew"}-patched" {} (''
    cp -r "${brew}" "$out"
    chmod u+w "$out" "$out/Library/Homebrew/cmd"

    # Disable self-update behavior
    substituteInPlace "$out/Library/Homebrew/cmd/update.sh" \
      --replace-fail 'for DIR in "''${HOMEBREW_REPOSITORY}"' "for DIR in "

    # Disable vendored Ruby
    ruby_sh="$out/Library/Homebrew/utils/ruby.sh"
    if [[ -e "$ruby_sh" ]] && grep "setup-ruby-path" "$ruby_sh"; then
      chmod u+w "$ruby_sh"
      echo -e "setup-ruby-path() { export HOMEBREW_RUBY_PATH=\"${ruby}/bin/ruby\"; }" >>"$ruby_sh"
    fi
  '' + lib.optionalString (brew ? version) ''
    # Embed version number instead of checking with git
    brew_sh="$out/Library/Homebrew/brew.sh"
    chmod u+w "$out/Library/Homebrew" "$brew_sh"
    sed -i -e 's/^HOMEBREW_VERSION=.*/HOMEBREW_VERSION="${brew.version}"/g' "$brew_sh"

    # 4.3.5: Clear GIT_REVISION to bypass caching mechanism
    sed -i -e 's/^GIT_REVISION=.*/GIT_REVISION=""; HOMEBREW_VERSION="${brew.version}"/g' "$brew_sh"
  '');
in {
  options = {
    nix-homebrew = {
      enable = lib.mkOption {
        description = ''
          Whether to install Homebrew.
        '';
        type = types.bool;
        default = false;
      };
      enableRosetta = lib.mkOption {
        description = ''
          Whether to set up the Homebrew prefix for Rosetta 2.

          This is only supported on Apple Silicon Macs.
        '';
        type = types.bool;
        default = false;
      };
      package = lib.mkOption {
        description = ''
          The homebrew package itself.
        '';
        type = types.package;
      };
      taps = lib.mkOption {
        description = ''
          A set of Nix-managed taps.

          These are applied to the default prefixes.
        '';
        type = types.attrsOf types.package;
        default = {};
        example = lib.literalExpression ''
          {
            "homebrew/homebrew-core" = pkgs.fetchFromGitHub {
              owner = "homebrew";
              repo = "homebrew-core";
              rev = "...";
              hash = "...";
            };
          }
        '';
      };
      mutableTaps = lib.mkOption {
        description = ''
          Whether to allow imperative management of taps.

          When enabled, taps can be managed via `brew tap` and
          `brew update`.

          When disabled, the auto-update functionality is also
          automatically disabled with `HOMEBREW_NO_AUTO_UPDATE=1`.
        '';
        type = types.bool;
        default = true;
      };
      autoMigrate = lib.mkOption {
        description = ''
          Whether to allow nix-homebrew to automatically migrate existing Homebrew installations.

          When enabled, the activation script will automatically delete
          Homebrew repositories while keeping installed packages.
        '';
        type = types.bool;
        default = false;
      };
      user = lib.mkOption {
        description = ''
          The user owning the Homebrew directories.
        '';
        type = types.str;
      };
      group = lib.mkOption {
        description = ''
          The group owning the Homebrew directories.
        '';
        type = types.str;
        default = "admin";
      };

      # Advanced options

      prefixes = lib.mkOption {
        description = ''
          A set of Homebrew prefixes to set up.

          Usually you don't need to configure this and sensible
          defaults are already set up.
        '';
        type = types.attrsOf prefixType;
      };
      defaultArm64Prefix = lib.mkOption {
        description = ''
          Key of the default Homebrew prefix for ARM64 macOS.
        '';
        internal = true;
        type = types.str;
        default = "/opt/homebrew";
      };
      defaultIntelPrefix = lib.mkOption {
        description = ''
          Key of the default Homebrew prefix for Intel macOS or Rosetta 2.
        '';
        internal = true;
        type = types.str;
        default = "/usr/local";
      };
      extraEnv = lib.mkOption {
        description = ''
          Extra environment variables to set for Homebrew.
        '';
        type = types.attrsOf types.str;
        default = {};
        example = lib.literalExpression ''
          {
            HOMEBREW_NO_ANALYTICS = "1";
          }
        '';
      };
      patchBrew = lib.mkOption {
        description = ''
          Whether to attempt to patch Homebrew to suppress self-updating.
        '';
        type = types.bool;
        default = true;
      };

      # Shell integrations
      enableBashIntegration = lib.mkEnableOption "homebrew bash integration" // {
        default = true;
      };

      enableFishIntegration = lib.mkEnableOption "homebrew fish integration" // {
        default = true;
      };

      enableZshIntegration = lib.mkEnableOption "homebrew zsh integration" // {
        default = true;
      };
    };
  };

  config = lib.mkIf (cfg.enable) {
    assertions = [
      {
        assertion = cfg.enableRosetta -> pkgs.stdenv.hostPlatform.isAarch64;
        message = "nix-homebrew.enableRosetta is set to true but this isn't an Apple Silicon Mac";
      }
      {
        # nix-darwin has migrated away from user activation in
        # <https://github.com/LnL7/nix-darwin/pull/1341>.
        assertion = options.system ? primaryUser;
        message = "Please update your nix-darwin version to use system-wide activation";
      }
    ];

    nix-homebrew = {
      prefixes = {
        "/opt/homebrew" = {
          enable = pkgs.stdenv.hostPlatform.isAarch64;
          library = "/opt/homebrew/Library";
          taps = cfg.taps;
        };
        "/usr/local" = {
          enable = pkgs.stdenv.hostPlatform.isx86_64 || cfg.enableRosetta;
          library = "/usr/local/Homebrew/Library";
          taps = cfg.taps;
        };
      };
    };

    # Shell integrations
    programs.bash.interactiveShellInit = lib.mkIf cfg.enableBashIntegration ''
      eval "$(brew shellenv 2>/dev/null || true)"
    '';

    programs.zsh.interactiveShellInit = lib.mkIf cfg.enableZshIntegration ''
      eval "$(brew shellenv 2>/dev/null || true)"
    '';

    programs.fish.interactiveShellInit = lib.mkIf cfg.enableFishIntegration ''
      brew shellenv 2>/dev/null | source || true
    '';

    environment.systemPackages = [ brewLauncher ];
    system.activationScripts = {
      # Set up the Homebrew prefixes before nix-darwin's homebrew
      # activation takes place.
      homebrew.text = lib.mkBefore ''
        ${config.system.activationScripts.setup-homebrew.text}
      '';
      setup-homebrew.text = ''
        >&2 echo "setting up Homebrew prefixes..."
        ${setupHomebrew}
      '';
    };

    # disable the install homebrew check
    # see https://github.com/LnL7/nix-darwin/pull/1178 and https://github.com/zhaofengli/nix-homebrew/issues/45
    system.checks.text = lib.mkIf config.homebrew.enable (lib.mkBefore ''
      # Ignore unused variable in nix-darwin versions without it
      # shellcheck disable=SC2034
      INSTALLING_HOMEBREW=1
    '');
  };
}
