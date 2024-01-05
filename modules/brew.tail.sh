# -----
# The following is copied from upstream bin/brew
# Copyright (c) 2009-present, Homebrew contributors
# -----

# nix-homebrew:
# Run scripts/update-brew-tail.sh to update this

# Load Homebrew's variable configuration files from disk.
export_homebrew_env_file() {
  local env_file

  env_file="${1}"
  [[ -r "${env_file}" ]] || return 0
  while read -r line
  do
    # only load HOMEBREW_* lines
    [[ "${line}" = "HOMEBREW_"* ]] || continue
    export "${line?}"
  done <"${env_file}"
}

# First, load the system-wide configuration.
unset SYSTEM_ENV_TAKES_PRIORITY
if [[ -n "${HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY-}" ]]
then
  SYSTEM_ENV_TAKES_PRIORITY="1"
else
  export_homebrew_env_file "/etc/homebrew/brew.env"
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

# If the system configuration takes priority, load it last.
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
  PATH
  SSH_TTY
  SUDO_USER
  TMUX
  XDG_CACHE_HOME
  XDG_RUNTIME_DIR
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

export HOMEBREW_BREW_FILE
export HOMEBREW_PREFIX
export HOMEBREW_REPOSITORY
export HOMEBREW_LIBRARY
export HOMEBREW_USER_CONFIG_HOME

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

# filter the user environment
PATH="/usr/bin:/bin:/usr/sbin:/sbin"

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
unset VAR ENV_VAR_NAMES

exec /usr/bin/env -i "${FILTERED_ENV[@]}" /bin/bash "${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$@"
