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

{ pkgs, lib, config, ... }:
let
  inherit (lib) types;

  # When this file exists under $HOMEBREW_PREFIX or a specific
  # tap, it means it's managed by us.
  nixMarker = ".managed_by_nix_darwin";

  cfg = config.nix-homebrew;

  tools = pkgs.callPackage ../pkgs { };

  # TODO: Maybe don't provide a default at all
  defaultBrew = pkgs.fetchFromGitHub {
    owner = "homebrew";
    repo = "brew";
    rev = "eff45ef570f265e226f14ce91da72d7a6e7d516a";
    sha256 = "sha256-4hoGm5PUYmz091Pqrii4rpfsLsE7/gjIThHVBq6Vquk=";
  };

  brew = if cfg.patchBrew then patchBrew cfg.package else cfg.package;

  prefixType = types.submodule ({ name, ... }: {
    options = {
      enable = lib.mkOption {
        description = lib.mdDoc ''
          Whether to set up this Homebrew prefix.
        '';
      };
      prefix = lib.mkOption {
        description = lib.mdDoc ''
          The Homebrew prefix.

          By default, it's `/opt/homebrew` for Apple Silicon Macs and
          `/usr/local` for Intel Macs.
        '';
        type = types.str;
        default = name;
      };
      library = lib.mkOption {
        description = lib.mdDoc ''
          The Homebrew library.

          By default, it's `/opt/homebrew/Library` for Apple Silicon Macs and
          `/usr/local/Homebrew/Library` for Intel Macs.
        '';
        type = types.str;
      };
      taps = lib.mkOption {
        description = lib.mdDoc ''
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
    '' + ''
      # -----
      # The following is copied from upstream bin/brew
      # Copyright (c) 2009-present, Homebrew contributors
      # -----

      # Copy and export all HOMEBREW_* variables previously mentioned in
      # manpage or used elsewhere by Homebrew.
      
      # These variables are allowed to be set by the user as, e.g., `HOMEBREW_BROWSER`.
      MANPAGE_VARS=(
        BAT_CONFIG_PATH
        BAT_THEME
        BROWSER
        DISPLAY
        EDITOR
        NO_COLOR
      )
      for VAR in "''${MANPAGE_VARS[@]}"
      do
        # Skip if variable value is empty.
        [[ -z "''${!VAR:-}" ]] && continue
      
        VAR_NEW="HOMEBREW_''${VAR}"
        # Skip if existing HOMEBREW_* variable is set.
        [[ -n "''${!VAR_NEW:-}" ]] && continue
        export "''${VAR_NEW}"="''${!VAR}"
      done
      
      # We don't want to take the user's value for, e.g., `HOMEBREW_PATH` here!
      USED_BY_HOMEBREW_VARS=(
        CODESPACES
        DBUS_SESSION_BUS_ADDRESS
        PATH
        TMUX
        XDG_RUNTIME_DIR
      )
      for VAR in "''${USED_BY_HOMEBREW_VARS[@]}"
      do
        # Skip if variable value is empty.
        [[ -z "''${!VAR:-}" ]] && continue
      
        # We unconditionally override `HOMEBREW_*` here.
        VAR_NEW="HOMEBREW_''${VAR}"
        export "''${VAR_NEW}"="''${!VAR}"
      done
      
      unset VAR VAR_NEW MANPAGE_VARS USED_BY_HOMEBREW_VARS

      # set from user environment
      # shellcheck disable=SC2154
      # Use VISUAL if HOMEBREW_EDITOR and EDITOR are unset.
      if [[ -z "''${HOMEBREW_EDITOR:-}" && -n "''${VISUAL:-}" ]]
      then
        export HOMEBREW_EDITOR="''${VISUAL}"
      fi
      
      # set from user environment
      # shellcheck disable=SC2154
      # Set CI variable for Azure Pipelines and Jenkins
      # (Set by default on GitHub Actions, Circle and Travis CI)
      if [[ -z "''${CI:-}" ]] && [[ -n "''${TF_BUILD:-}" || -n "''${JENKINS_HOME:-}" ]]
      then
        export CI="1"
      fi
      
      # filter the user environment
      PATH="/usr/bin:/bin:/usr/sbin:/sbin"
      
      FILTERED_ENV=()
      ENV_VAR_NAMES=(
        HOME SHELL PATH TERM TERMINFO TERMINFO_DIRS COLUMNS DISPLAY LOGNAME USER CI SSH_AUTH_SOCK SUDO_ASKPASS
        http_proxy https_proxy ftp_proxy no_proxy all_proxy HTTPS_PROXY FTP_PROXY ALL_PROXY
      )
      # Filter all but the specific variables.
      for VAR in "''${ENV_VAR_NAMES[@]}" "''${!HOMEBREW_@}"
      do
        # Skip if variable value is empty.
        [[ -z "''${!VAR:-}" ]] && continue
      
        FILTERED_ENV+=("''${VAR}=''${!VAR}")
      done
      
      if [[ -n "''${CI:-}" ]]
      then
        for VAR in "''${!GITHUB_@}"
        do
          # Skip if variable value is empty.
          [[ -z "''${!VAR:-}" ]] && continue
          # Skip variables that look like tokens.
          [[ "''${VAR}" = *TOKEN* ]] && continue
      
          FILTERED_ENV+=("''${VAR}=''${!VAR}")
        done
      fi
      unset VAR ENV_VAR_NAMES

      exec /usr/bin/env -i "''${FILTERED_ENV[@]}" /bin/bash "''${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$@"
    '');
  in pkgs.substituteAll {
    name = "brew";
    src = template;
    isExecutable = true;

    inherit (prefix) prefix library;
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
      ohai 'Run ''${tty_bold}softwareupdate --install-rosetta''${tty_reset} to install it.'
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

  # Patch Homebrew to disable self-update behavior
  patchBrew = brew: pkgs.runCommandLocal "${brew.name}-patched" {} ''
    cp -r "${brew}" "$out"
    chmod u+w "$out" "$out/Library/Homebrew/cmd"

    substituteInPlace "$out/Library/Homebrew/cmd/update.sh" \
      --replace 'for DIR in "''${HOMEBREW_REPOSITORY}"' "for DIR in "
  '';
in {
  options = {
    nix-homebrew = {
      enable = lib.mkOption {
        description = lib.mdDoc ''
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
        description = lib.mdDoc ''
          The homebrew package itself.
        '';
        type = types.package;
        default = defaultBrew;
        defaultText = lib.literalExpression "(default Homebrew package)";
      };
      taps = lib.mkOption {
        description = lib.mdDoc ''
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
        description = lib.mdDoc ''
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
        description = lib.mdDoc ''
          The user owning the Homebrew directories.
        '';
        type = types.str;
      };
      group = lib.mkOption {
        description = lib.mdDoc ''
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
        description = lib.mdDoc ''
          Key of the default Homebrew prefix for ARM64 macOS.
        '';
        internal = true;
        type = types.str;
        default = "/opt/homebrew";
      };
      defaultIntelPrefix = lib.mkOption {
        description = lib.mdDoc ''
          Key of the default Homebrew prefix for Intel macOS or Rosetta 2.
        '';
        internal = true;
        type = types.str;
        default = "/usr/local";
      };
      extraEnv = lib.mkOption {
        description = lib.mdDoc ''
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
    };
  };

  config = lib.mkIf (cfg.enable) {
    assertions = [
      {
        assertion = cfg.enableRosetta -> pkgs.stdenv.hostPlatform.isAarch64;
        message = "nix-homebrew.enableRosetta is set to true but this isn't an Apple Silicon Mac";
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

    environment.systemPackages = [ brewLauncher ];
    system.activationScripts = {
      # We set up a new system activation step that sets up Homebrew
      preActivation.text = lib.mkAfter ''
        ${config.system.activationScripts.setup-homebrew.text}
      '';
      setup-homebrew.text = ''
        ${setupHomebrew}
      '';
    };
  };
}
