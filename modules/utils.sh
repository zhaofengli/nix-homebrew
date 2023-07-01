# Snippets from the Homebrew install script.
#
# BSD 2-Clause License
# Copyright (c) 2009-present, Homebrew contributors
# All rights reserved.
#
# Uses:
#
# - HOMEBREW_PREFIX
# - HOMEBREW_LIBRARY
# - NIX_HOMEBREW_UID
# - NIX_HOMEBREW_GID

# TODO: Use Nix-provided utils
# GNU stat behaves differently
STAT_PRINTF=("/usr/bin/stat" "-f")
PERMISSION_FORMAT="%A"

CHMOD=("/bin/chmod")
CHOWN=("/usr/sbin/chown")
CHGRP=("/usr/bin/chgrp")
MKDIR=("/bin/mkdir" "-p")
TOUCH=("/usr/bin/touch")
INSTALL=("/usr/bin/install" -d -o "root" -g "wheel" -m "0755")

# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

error() {
  printf "${tty_red}Error${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

get_permission() {
  "${STAT_PRINTF[@]}" "${PERMISSION_FORMAT}" "$1"
}

user_only_chmod() {
  [[ -d "$1" ]] && [[ "$(get_permission "$1")" != 75[0145] ]]
}

exists_but_not_writable() {
  [[ -e "$1" ]] && ! [[ -r "$1" && -w "$1" && -x "$1" ]]
}

user_only_chmod() {
  [[ -d "$1" ]] && [[ "$(get_permission "$1")" != 75[0145] ]]
}

get_owner() {
  "${STAT_PRINTF[@]}" "%u" "$1"
}

file_not_owned() {
  [[ "$(get_owner "$1")" != "${NIX_HOMEBREW_UID}" ]]
}

get_group() {
  "${STAT_PRINTF[@]}" "%g" "$1"
}

file_not_grpowned() {
  [[ " ${NIX_HOMEBREW_GID} " != *" $(get_group "$1") "* ]]
}

# HOMEBREW_PREFIX
initialize_prefix() {
  # Keep relatively in sync with
  # https://github.com/Homebrew/brew/blob/master/Library/Homebrew/keg.rb
  directories=(
    bin etc include lib sbin share opt var
    Frameworks
    etc/bash_completion.d lib/pkgconfig
    share/aclocal share/doc share/info share/locale share/man
    share/man/man1 share/man/man2 share/man/man3 share/man/man4
    share/man/man5 share/man/man6 share/man/man7 share/man/man8
    var/log var/homebrew var/homebrew/linked
    bin/brew
  )
  group_chmods=()
  for dir in "${directories[@]}"
  do
    if exists_but_not_writable "${HOMEBREW_PREFIX}/${dir}"
    then
      group_chmods+=("${HOMEBREW_PREFIX}/${dir}")
    fi
  done

  # zsh refuses to read from these directories if group writable
  directories=(share/zsh share/zsh/site-functions)
  zsh_dirs=()
  for dir in "${directories[@]}"
  do
    zsh_dirs+=("${HOMEBREW_PREFIX}/${dir}")
  done

  directories=(
    bin etc include lib sbin share var opt
    share/zsh share/zsh/site-functions
    var/homebrew var/homebrew/linked
    Cellar Caskroom Frameworks
  )
  mkdirs=()
  for dir in "${directories[@]}"
  do
    if ! [[ -d "${HOMEBREW_PREFIX}/${dir}" ]]
    then
      mkdirs+=("${HOMEBREW_PREFIX}/${dir}")
    fi
  done

  user_chmods=()
  mkdirs_user_only=()
  if [[ "${#zsh_dirs[@]}" -gt 0 ]]
  then
    for dir in "${zsh_dirs[@]}"
    do
      if [[ ! -d "${dir}" ]]
      then
        mkdirs_user_only+=("${dir}")
      elif user_only_chmod "${dir}"
      then
        user_chmods+=("${dir}")
      fi
    done
  fi

  chmods=()
  if [[ "${#group_chmods[@]}" -gt 0 ]]
  then
    chmods+=("${group_chmods[@]}")
  fi
  if [[ "${#user_chmods[@]}" -gt 0 ]]
  then
    chmods+=("${user_chmods[@]}")
  fi

  chowns=()
  chgrps=()
  if [[ "${#chmods[@]}" -gt 0 ]]
  then
    for dir in "${chmods[@]}"
    do
      if file_not_owned "${dir}"
      then
        chowns+=("${dir}")
      fi
      if file_not_grpowned "${dir}"
      then
        chgrps+=("${dir}")
      fi
    done
  fi

  if [[ -d "${HOMEBREW_PREFIX}" ]]
  then
    if [[ "${#chmods[@]}" -gt 0 ]]
    then
      "${CHMOD[@]}" "u+rwx" "${chmods[@]}"
    fi
    if [[ "${#group_chmods[@]}" -gt 0 ]]
    then
      "${CHMOD[@]}" "g+rwx" "${group_chmods[@]}"
    fi
    if [[ "${#user_chmods[@]}" -gt 0 ]]
    then
      "${CHMOD[@]}" "go-w" "${user_chmods[@]}"
    fi
    if [[ "${#chowns[@]}" -gt 0 ]]
    then
      "${CHOWN[@]}" "${NIX_HOMEBREW_UID}" "${chowns[@]}"
    fi
    if [[ "${#chgrps[@]}" -gt 0 ]]
    then
      "${CHGRP[@]}" "${NIX_HOMEBREW_GID}" "${chgrps[@]}"
    fi
  else
    "${INSTALL[@]}" "${HOMEBREW_PREFIX}"
  fi

  if [[ "${#mkdirs[@]}" -gt 0 ]]
  then
    "${MKDIR[@]}" "${mkdirs[@]}"
    "${CHMOD[@]}" "ug=rwx" "${mkdirs[@]}"
    if [[ "${#mkdirs_user_only[@]}" -gt 0 ]]
    then
      "${CHMOD[@]}" "go-w" "${mkdirs_user_only[@]}"
    fi
    "${CHOWN[@]}" "${NIX_HOMEBREW_UID}" "${mkdirs[@]}"
    "${CHGRP[@]}" "${NIX_HOMEBREW_GID}" "${mkdirs[@]}"
  fi

  if ! [[ -d "${HOMEBREW_LIBRARY}" ]]
  then
    "${MKDIR[@]}" "${HOMEBREW_LIBRARY}"
  fi
  "${CHOWN[@]}" "-R" "${NIX_HOMEBREW_UID}:${NIX_HOMEBREW_GID}" "${HOMEBREW_LIBRARY}"

  "${TOUCH[@]}" "${HOMEBREW_PREFIX}/.managed_by_nix_darwin"
}

# vim: set et ts=2 sw=2:
