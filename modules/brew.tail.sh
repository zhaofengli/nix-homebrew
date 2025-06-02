# -----
# The following is copied from upstream bin/brew
# Copyright (c) 2009-present, Homebrew contributors
# -----

# nix-homebrew:
# Run scripts/update-brew-tail.sh to update this

# Use HOMEBREW_BREW_WRAPPER if set.
export HOMEBREW_ORIGINAL_BREW_FILE="${HOMEBREW_BREW_FILE}"
if [[ -n "${HOMEBREW_BREW_WRAPPER:-}" ]]
then
  HOMEBREW_BREW_FILE="${HOMEBREW_BREW_WRAPPER}"
fi

# These variables are exported in this file and are not allowed to be overridden by the user.
BIN_BREW_EXPORTED_VARS=(
  HOMEBREW_BREW_FILE
  HOMEBREW_PREFIX
  HOMEBREW_REPOSITORY
  HOMEBREW_LIBRARY
  HOMEBREW_USER_CONFIG_HOME
  HOMEBREW_ORIGINAL_BREW_FILE
)

# Load Homebrew's variable configuration files from disk.
export_homebrew_env_file() {
  local env_file

  env_file="${1}"
  [[ -r "${env_file}" ]] || return 0
  while read -r line
  do
    # only load HOMEBREW_* lines
    [[ "${line}" = "HOMEBREW_"* ]] || continue

    # forbid overriding variables that are set in this file
    local invalid_variable
    for VAR in "${BIN_BREW_EXPORTED_VARS[@]}"
    do
      [[ "${line}" = "${VAR}"* ]] && invalid_variable="${VAR}"
    done
    [[ -n "${invalid_variable:-}" ]] && continue

    export "${line?}"
  done <"${env_file}"
}

# First, load the system-wide configuration.
export_homebrew_env_file "/etc/homebrew/brew.env"

unset SYSTEM_ENV_TAKES_PRIORITY
if [[ -n "${HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY-}" ]]
then
  SYSTEM_ENV_TAKES_PRIORITY="1"
fi

# Next, load the prefix configuration
export_homebrew_env_file "${HOMEBREW_PREFIX}/etc/homebrew/brew.env"

# Finally, load the user configuration
if [[ -n "${XDG_CONFIG_HOME-}" ]]
then
  HOMEBREW_USER_CONFIG_HOME="${XDG_CONFIG_HOME}/homebrew"
else
  HOMEBREW_USER_CONFIG_HOME="${HOME}/.homebrew"
fi

export_homebrew_env_file "${HOMEBREW_USER_CONFIG_HOME}/brew.env"

# If the system configuration takes priority, load it again to override any previous settings.
if [[ -n "${SYSTEM_ENV_TAKES_PRIORITY-}" ]]
then
  export_homebrew_env_file "/etc/homebrew/brew.env"
fi

# Copy and export all HOMEBREW_* variables previously mentioned in
# manpage or used elsewhere by Homebrew.

# These variables are allowed to be set by the user as, e.g., `HOMEBREW_BROWSER`.
MANPAGE_VARS=(
  BAT_CONFIG_PATH
  BAT_THEME
  BROWSER
  BUNDLE_USER_CACHE
  DISPLAY
  EDITOR
  NO_COLOR
)
for VAR in "${MANPAGE_VARS[@]}"
do
  # Skip if variable value is empty.
  [[ -z "${!VAR:-}" ]] && continue

  VAR_NEW="HOMEBREW_${VAR}"
  # Skip if existing HOMEBREW_* variable is set.
  [[ -n "${!VAR_NEW:-}" ]] && continue
  export "${VAR_NEW}"="${!VAR}"
done

# We don't want to take the user's value for, e.g., `HOMEBREW_PATH` here!
USED_BY_HOMEBREW_VARS=(
  CODESPACES
  COLORTERM
  DBUS_SESSION_BUS_ADDRESS
  NODENV_ROOT
  PATH
  PYENV_ROOT
  RBENV_ROOT
  SSH_TTY
  SUDO_USER
  TMPDIR
  TMUX
  XDG_CACHE_HOME
  XDG_DATA_DIRS
  XDG_RUNTIME_DIR
  ZDOTDIR
)
for VAR in "${USED_BY_HOMEBREW_VARS[@]}"
do
  # Skip if variable value is empty.
  [[ -z "${!VAR:-}" ]] && continue

  # We unconditionally override `HOMEBREW_*` here.
  VAR_NEW="HOMEBREW_${VAR}"
  export "${VAR_NEW}"="${!VAR}"
done

unset VAR VAR_NEW MANPAGE_VARS USED_BY_HOMEBREW_VARS

for VAR in "${BIN_BREW_EXPORTED_VARS[@]}"
do
  export "${VAR?}"
done

# set from user environment
# shellcheck disable=SC2154
# Use VISUAL if HOMEBREW_EDITOR and EDITOR are unset.
if [[ -z "${HOMEBREW_EDITOR:-}" && -n "${VISUAL:-}" ]]
then
  export HOMEBREW_EDITOR="${VISUAL}"
fi

# set from user environment
# shellcheck disable=SC2154
# Set CI variable for Azure Pipelines and Jenkins
# (Set by default on GitHub Actions, Circle and Travis CI)
if [[ -z "${CI:-}" ]] && [[ -n "${TF_BUILD:-}" || -n "${JENKINS_HOME:-}" ]]
then
  export CI="1"
fi

if [[ -n "${GITHUB_ACTIONS:-}" && -n "${ImageOS:-}" && -n "${ImageVersion:-}" ]]
then
  export HOMEBREW_GITHUB_HOSTED_RUNNER=1
fi

# don't filter the environment for `brew bundle (exec|env|sh)`
if [[ "${1:-}" == "bundle" ]]
then
  if [[ "${2:-}" == "exec" || "${2:-}" == "env" || "${2:-}" == "sh" ]]
  then
    exec /bin/bash -p "${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$@"
    exit $?
  fi
fi

# filter the user environment
PATH="@runtimePath@:/usr/bin:/bin:/usr/sbin:/sbin"

FILTERED_ENV=()
ENV_VAR_NAMES=(
  HOME SHELL PATH TERM TERMINFO TERMINFO_DIRS COLUMNS DISPLAY LOGNAME USER CI SSH_AUTH_SOCK SUDO_ASKPASS
  http_proxy https_proxy ftp_proxy no_proxy all_proxy HTTPS_PROXY FTP_PROXY ALL_PROXY
)
# Filter all but the specific variables.
for VAR in "${ENV_VAR_NAMES[@]}" "${!HOMEBREW_@}"
do
  # Skip if variable value is empty.
  [[ -z "${!VAR:-}" ]] && continue

  FILTERED_ENV+=("${VAR}=${!VAR}")
done

if [[ -n "${CI:-}" ]]
then
  for VAR in "${!GITHUB_@}"
  do
    # Skip if variable value is empty.
    [[ -z "${!VAR:-}" ]] && continue
    # Skip variables that look like tokens.
    [[ "${VAR}" = *TOKEN* ]] && continue

    FILTERED_ENV+=("${VAR}=${!VAR}")
  done
fi

if [[ -n "${HOMEBREW_RDBG:-}" ]]
then
  for VAR in "${!RUBY_DEBUG_@}"
  do
    # Skip if variable value is empty.
    [[ -z "${!VAR:-}" ]] && continue

    FILTERED_ENV+=("${VAR}=${!VAR}")
  done
fi

unset VAR ENV_VAR_NAMES

exec /usr/bin/env -i "${FILTERED_ENV[@]}" /bin/bash -p "${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$@"
