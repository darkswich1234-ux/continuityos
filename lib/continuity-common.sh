#!/usr/bin/env bash
# ContinuityOS — shared library for all continuity-* tools.
# Sourced by the CLI; not executed directly.
# shellcheck shell=bash

CONTINUITY_VERSION="0.1.0"
CONTINUITY_NAME="ContinuityOS"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  _c_reset=$'\033[0m'; _c_dim=$'\033[2m'; _c_red=$'\033[31m'
  _c_grn=$'\033[32m'; _c_ylw=$'\033[33m'; _c_blu=$'\033[34m'
else
  _c_reset=''; _c_dim=''; _c_red=''; _c_grn=''; _c_ylw=''; _c_blu=''
fi

continuity_info()  { printf '%s[continuity]%s %s\n' "$_c_blu" "$_c_reset" "$*" >&2; }
continuity_ok()    { printf '%s[continuity]%s %s\n' "$_c_grn" "$_c_reset" "$*" >&2; }
continuity_warn()  { printf '%s[continuity]%s %s\n' "$_c_ylw" "$_c_reset" "$*" >&2; }
continuity_error() { printf '%s[continuity]%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
continuity_debug() { [ "${CONTINUITY_DEBUG:-0}" = "1" ] && printf '%s[continuity:debug]%s %s\n' "$_c_dim" "$_c_reset" "$*" >&2 || true; }

continuity_die() { continuity_error "$@"; exit 1; }

continuity_have() { command -v "$1" >/dev/null 2>&1; }

continuity_require() {
  local cmd="$1" hint="${2:-}"
  if ! continuity_have "$cmd"; then
    if [ -n "$hint" ]; then
      continuity_die "required command '$cmd' not found — $hint"
    fi
    continuity_die "required command '$cmd' not found"
  fi
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
continuity_paths() {
  : "${XDG_CONFIG_HOME:=$HOME/.config}"
  : "${XDG_DATA_HOME:=$HOME/.local/share}"
  : "${XDG_STATE_HOME:=$HOME/.local/state}"
  : "${XDG_CACHE_HOME:=$HOME/.cache}"

  CONTINUITY_CONFIG_DIR="${CONTINUITY_CONFIG_DIR:-$XDG_CONFIG_HOME/continuity}"
  CONTINUITY_PREFIX_ROOT="${CONTINUITY_PREFIX_ROOT:-$XDG_DATA_HOME/universal-prefixes}"
  CONTINUITY_LAUNCHER_DIR="${CONTINUITY_LAUNCHER_DIR:-$XDG_DATA_HOME/applications/continuity}"
  CONTINUITY_STATE_DIR="${CONTINUITY_STATE_DIR:-$XDG_STATE_HOME/continuity}"
  CONTINUITY_ASSET_DIR="${CONTINUITY_ASSET_DIR:-$XDG_DATA_HOME/continuity/assets}"
  CONTINUITY_LOG="${CONTINUITY_LOG:-$CONTINUITY_STATE_DIR/continuity.log}"
  export CONTINUITY_CONFIG_DIR CONTINUITY_PREFIX_ROOT
  export CONTINUITY_LAUNCHER_DIR CONTINUITY_STATE_DIR CONTINUITY_ASSET_DIR CONTINUITY_LOG
  return 0
}

# Load user overrides. Only $CONTINUITY_* keys are honoured; the file is refused
# if it is group/world writable, because we source it.
continuity_load_env() {
  # Establish the defaults first: the config file can only *override* them, and
  # every caller expects CONTINUITY_* to be bound afterwards (set -u).
  continuity_paths
  local file="$CONTINUITY_CONFIG_DIR/environment.conf"
  [ -r "$file" ] || return 0
  if [ "$(stat -c '%u' "$file" 2>/dev/null || echo 0)" != "$(id -u)" ]; then
    continuity_warn "ignoring $file (not owned by you)"
  elif [ -n "$(find "$file" -perm /022 -print -quit 2>/dev/null)" ]; then
    continuity_warn "ignoring $file (world/group writable)"
  else
    # shellcheck disable=SC1090
    . "$file"
  fi
  continuity_paths
}

# ContinuityOS-owned dirs with the right permissions.
continuity_ensure_dirs() {
  mkdir -p "$CONTINUITY_PREFIX_ROOT" "$CONTINUITY_LAUNCHER_DIR" \
           "$CONTINUITY_STATE_DIR" "$CONTINUITY_CONFIG_DIR" 2>/dev/null || true
  chmod 700 "$CONTINUITY_PREFIX_ROOT" "$CONTINUITY_STATE_DIR" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Naming
# ---------------------------------------------------------------------------
continuity_slugify() {
  local raw="$1" slug
  slug="$(printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-\+//' -e 's/-\+$//')"
  slug="${slug:0:64}"
  [ -n "$slug" ] || slug="windows-app"
  printf '%s' "$slug"
}

# Name -> slug for an .exe: "MyGame-Setup.exe" -> mygame-setup
continuity_slug_for_file() {
  local path="$1" base
  base="$(basename -- "$path")"
  base="${base%.*}"
  continuity_slugify "$base"
}

continuity_prefix_dir() { printf '%s/%s' "$CONTINUITY_PREFIX_ROOT" "$1"; }

# Proton uses <compatdata>/pfx as its Wine prefix; older ContinuityOS prefixes
# were plain WINEPREFIX directories at the slug root.
continuity_prefix_wine_dir() {
  local dir
  dir="$(continuity_prefix_dir "$1")"
  if [ -d "$dir/pfx" ]; then printf '%s/pfx' "$dir"; else printf '%s' "$dir"; fi
}

continuity_prefix_drive_c() {
  local dir
  dir="$(continuity_prefix_dir "$1")"
  if [ -d "$dir/pfx/drive_c" ]; then printf '%s/pfx/drive_c' "$dir"; else printf '%s/drive_c' "$dir"; fi
}

# Executables that are part of the Windows installation itself rather than
# programs the user installed. Registering these would fill the application menu
# with Internet Explorer, Media Player and WordPad from every fresh prefix.
# Shared so the launcher writer and the launch path agree on what to skip.
continuity_is_system_exe() {
  local name rel
  rel="$1"
  name="${rel##*/}"
  case "$rel" in
    windows/*|*/windows/*|*/Windows/*) return 0 ;;
    *Microsoft.NET*|*Installer*|*WinMetadata*) return 0 ;;
    */unins*.exe|*/Unins*.exe|*/uninstall*.exe) return 0 ;;
    *"/Internet Explorer/"*|*"/Windows Media Player/"*) return 0 ;;
    *"/Windows NT/Accessories/"*) return 0 ;;
  esac
  case "$name" in
    rundll32.exe|msiexec.exe|regsvr32.exe|cmd.exe|explorer.exe) return 0 ;;
    iexplore.exe|wmplayer.exe|wordpad.exe|notepad.exe|regedit.exe) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Distribution family
# ---------------------------------------------------------------------------
# The engine is not Arch-only: it also runs from an ordinary user account on a
# Debian/Ubuntu, Fedora or openSUSE install (see install.sh). Anything
# that prints a "how do I fix this" command asks here instead of hardcoding
# pacman, so a hint is never a command that does not exist on the machine.
continuity_family() {
  if [ -n "${CONTINUITY_FAMILY:-}" ]; then printf '%s' "$CONTINUITY_FAMILY"; return 0; fi
  local id="" like=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    id="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )"
    # shellcheck disable=SC1091
    like="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}" )"
  fi
  case " ${id} ${like} " in
    *" arch "*)                              printf 'arch' ;   return 0 ;;
    *" debian "*|*" ubuntu "*)               printf 'debian' ; return 0 ;;
    *" fedora "*|*" rhel "*|*" centos "*)   printf 'fedora' ; return 0 ;;
    *" suse "*|*" opensuse "*)               printf 'suse' ;   return 0 ;;
  esac
  # A remix without usable os-release still has a package manager.
  if continuity_have pacman; then printf 'arch'
  elif continuity_have apt-get; then printf 'debian'
  elif continuity_have dnf; then printf 'fedora'
  elif continuity_have zypper; then printf 'suse'
  else printf 'unknown'; fi
}

# Existing 32-bit library directories, most specific first. Arch keeps them in
# /usr/lib32; Debian multiarch in /usr/lib/i386-linux-gnu; Fedora mixes them into
# /usr/lib (with the 64-bit tree in /usr/lib64).
continuity_lib32_dirs() {
  local d
  for d in /usr/lib32 /usr/lib/i386-linux-gnu /usr/lib/i686-linux-gnu; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
  if [ "$(continuity_family)" = "fedora" ] && [ -d /usr/lib ]; then
    printf '/usr/lib\n'
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Package install hints — one logical package name, one command per family.
# ---------------------------------------------------------------------------
# Only packages this project actually verifies in packages/*.list and
# continuity-shakedown are mapped. A logical name with no mapping for the local
# family is omitted, which lets the caller fall back to a sentence instead of
# printing a command the distribution cannot run.
continuity_pkg_name() {
  local logical="$1" fam
  fam="$(continuity_family)"
  case "$fam:$logical" in
    arch:vulkan-tools)      printf 'vulkan-tools' ;;
    arch:mesa)              printf 'mesa' ;;
    arch:mesa32)            printf 'lib32-mesa' ;;
    arch:vulkan-loader32)   printf 'lib32-vulkan-icd-loader' ;;
    arch:vulkan-amd)        printf 'vulkan-radeon' ;;
    arch:vulkan-amd32)      printf 'lib32-vulkan-radeon' ;;
    arch:vulkan-intel)      printf 'vulkan-intel' ;;
    arch:vulkan-intel32)    printf 'lib32-vulkan-intel' ;;
    arch:nvidia)            printf 'nvidia-utils' ;;
    arch:nvidia32)          printf 'lib32-nvidia-utils' ;;
    arch:nvidia-dkms)       printf 'nvidia-open-dkms' ;;
    arch:gpu-driver-amd)    printf 'mesa linux-firmware' ;;
    arch:gpu-driver-intel)  printf 'mesa linux-firmware' ;;
    arch:gl32)              printf 'lib32-libgl' ;;
    arch:wine)              printf 'wine' ;;
    arch:linux-zen)         printf 'linux-zen' ;;
    # umu-launcher is deliberately absent: Arch ships it in the AUR only, so a
    # `pacman -S umu-launcher` hint would fail. continuity_umu_hint falls back
    # to the installer's own upstream download instead.
    arch:winetricks)        printf 'winetricks' ;;
    arch:xdg-utils)         printf 'xdg-utils' ;;
    arch:zstd)              printf 'zstd' ;;
    arch:steam)             printf 'steam' ;;
    arch:gamescope)         printf 'gamescope' ;;
    arch:mangohud)          printf 'mangohud' ;;
    arch:gamemode)          printf 'gamemode' ;;

    debian:vulkan-tools)    printf 'vulkan-tools' ;;
    debian:mesa)            printf 'mesa-vulkan-drivers' ;;
    debian:mesa32)          printf 'mesa-vulkan-drivers:i386' ;;
    debian:vulkan-loader32) printf 'libvulkan1:i386' ;;
    debian:vulkan-amd)      printf 'mesa-vulkan-drivers' ;;
    debian:vulkan-amd32)    printf 'mesa-vulkan-drivers:i386' ;;
    debian:vulkan-intel)    printf 'mesa-vulkan-drivers' ;;
    debian:vulkan-intel32)  printf 'mesa-vulkan-drivers:i386' ;;
    debian:nvidia)          printf 'nvidia-driver' ;;
    debian:nvidia32)        printf 'nvidia-driver-libs:i386' ;;
    debian:nvidia-dkms)     printf 'nvidia-driver' ;;
    debian:gl32)            printf 'libgl1:i386' ;;
    debian:wine)            printf 'wine' ;;
    debian:wine32)          printf 'wine32:i386' ;;
    debian:winetricks)      printf 'winetricks' ;;
    debian:xdg-utils)       printf 'xdg-utils' ;;
    debian:zstd)            printf 'zstd' ;;
    debian:gpu-driver-amd)  printf 'mesa-vulkan-drivers firmware-amd-graphics' ;;
    debian:gpu-driver-intel) printf 'mesa-vulkan-drivers firmware-misc-nonfree' ;;
    debian:mangohud)        printf 'mangohud' ;;
    debian:gamemode)        printf 'gamemode' ;;

    fedora:vulkan-tools)    printf 'vulkan-tools' ;;
    fedora:mesa)            printf 'mesa-vulkan-drivers' ;;
    fedora:mesa32)          printf 'mesa-vulkan-drivers.i686' ;;
    fedora:vulkan-loader32) printf 'vulkan-loader.i686' ;;
    fedora:vulkan-amd)      printf 'mesa-vulkan-drivers' ;;
    fedora:vulkan-amd32)    printf 'mesa-vulkan-drivers.i686' ;;
    fedora:vulkan-intel)    printf 'mesa-vulkan-drivers' ;;
    fedora:vulkan-intel32)  printf 'mesa-vulkan-drivers.i686' ;;
    fedora:nvidia)          printf 'akmod-nvidia' ;;
    fedora:nvidia32)        printf 'xorg-x11-drv-nvidia-libs.i686' ;;
    fedora:nvidia-dkms)     printf 'akmod-nvidia' ;;
    fedora:gl32)            printf 'mesa-libGL.i686' ;;
    fedora:wine)            printf 'wine' ;;
    fedora:umu-launcher)    printf 'umu-launcher' ;;
    fedora:winetricks)      printf 'winetricks' ;;
    fedora:xdg-utils)       printf 'xdg-utils' ;;
    fedora:zstd)            printf 'zstd' ;;
    fedora:gpu-driver-amd)  printf 'mesa-dri-drivers linux-firmware' ;;
    fedora:gpu-driver-intel) printf 'mesa-dri-drivers linux-firmware' ;;
    fedora:gamescope)       printf 'gamescope' ;;
    fedora:mangohud)        printf 'mangohud' ;;
    fedora:gamemode)        printf 'gamemode' ;;

    suse:xdg-utils)         printf 'xdg-utils' ;;
  esac
  return 0
}

# continuity_pkg_command <logical>... -> "sudo apt install …" for this machine,
# or nothing (exit 1) when none of the given names exist here. Names the local
# family does not know are skipped; duplicates are collapsed.
continuity_pkg_command() {
  local logical p fam names=() seen=" "
  fam="$(continuity_family)"
  for logical in "$@"; do
    p="$(continuity_pkg_name "$logical")"
    [ -n "$p" ] || continue
    case "$seen" in *" $p "*) continue ;; esac
    seen="$seen$p "
    names+=("$p")
  done
  [ "${#names[@]}" -gt 0 ] || return 1
  case "$fam" in
    arch)   printf 'sudo pacman -S %s' "${names[*]}" ;;
    fedora) printf 'sudo dnf install %s' "${names[*]}" ;;
    suse)   printf 'sudo zypper install %s' "${names[*]}" ;;
    debian)
      # 32-bit packages need the foreign architecture first or apt refuses them.
      case " ${names[*]} " in
        *':i386 '*) printf 'sudo dpkg --add-architecture i386 && sudo apt update && sudo apt install %s' "${names[*]}" ;;
        *)          printf 'sudo apt install %s' "${names[*]}" ;;
      esac
      ;;
    *) printf 'install: %s' "${names[*]}" ;;
  esac
  return 0
}

# The one-line remedy for a missing umu-run: a repository package where one
# exists, otherwise the upstream download the standalone installer uses.
continuity_umu_hint() {
  local cmd
  if cmd="$(continuity_pkg_command umu-launcher 2>/dev/null)"; then
    printf '%s' "$cmd"
    return 0
  fi
  printf 're-run this project\047s install.sh   (it installs umu-run next to the command)'
}

# ---------------------------------------------------------------------------
# Desktop entries (Exec= has NO shell: never emit ~, $VAR or backticks)
# ---------------------------------------------------------------------------
# Escape a string for the Exec key of a desktop entry.
continuity_exec_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\$/\\\$}"
  s="${s//\`/\\\`}"
  printf '"%s"' "$s"
}

continuity_refresh_desktop_db() {
  if continuity_have update-desktop-database; then
    update-desktop-database "$CONTINUITY_LAUNCHER_DIR" >/dev/null 2>&1 || true
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
continuity_confirm() {
  local prompt="$1"
  if [ "${CONTINUITY_ASSUME_YES:-0}" = "1" ] || [ "${ASSUME_YES:-0}" = "1" ]; then
    return 0
  fi
  [ -t 0 ] || return 1
  local reply
  read -r -p "$prompt [y/N] " reply
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

continuity_log() {
  mkdir -p "$CONTINUITY_STATE_DIR" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -Is)" "$*" >>"$CONTINUITY_LOG" 2>/dev/null || true
}

continuity_first_line() {
  local line
  IFS= read -r line || true
  printf '%s' "$line"
}

# Locate Proton installations for direct host invocation. GE-Proton is
# intentionally not treated as a supported standalone runner; upstream requires
# UMU for non-Steam GE-Proton use. CachyOS SLR Proton is the UMU default; the
# host-native CachyOS variant and Valve Proton can be selected for direct mode.
continuity_proton_roots() {
  local root candidate
  for root in \
    "$XDG_DATA_HOME/Steam/steamapps/common" \
    "$HOME/.steam/root/steamapps/common" \
    "$HOME/.steam/steam/steamapps/common" \
    "$HOME/.local/share/Steam/steamapps/common" \
    "/usr/share/steam/steamapps/common" \
    "$XDG_DATA_HOME/Steam/compatibilitytools.d" \
    "$HOME/.steam/root/compatibilitytools.d" \
    "$HOME/.steam/steam/compatibilitytools.d" \
    "$HOME/.local/share/Steam/compatibilitytools.d" \
    "/usr/share/steam/compatibilitytools.d" \
    "/usr/lib/steam/compatibilitytools.d" \
    "/opt/steam/compatibilitytools.d"; do
    [ -d "$root" ] || continue
    for candidate in "$root"/Proton* "$root"/GE-Proton* "$root"/proton-cachyos*; do
      [ -d "$candidate" ] && [ -x "$candidate/proton" ] || continue
      case "${candidate##*/}" in GE-Proton*|proton-cachyos-slr*) continue ;; esac
      printf '%s\n' "$candidate"
    done
  done
}

continuity_find_host_proton() {
  local candidate name
  while IFS= read -r candidate; do
    name="${candidate##*/}"
    case "${name,,}" in
      ge-proton*|proton-cachyos-slr*) continue ;;
    esac
    printf '%s\n' "$candidate"
    return 0
  done < <(continuity_proton_roots)
  return 1
}

continuity_resolve_proton() {
  local selector="$1" candidate wanted name normalized
  if [ -x "$selector/proton" ]; then
    case "${selector##*/}" in GE-Proton*|proton-cachyos-slr*) return 1 ;; esac
    readlink -f -- "$selector"
    return 0
  fi
  if [ -x "$selector" ] && [ "${selector##*/}" = "proton" ]; then
    case "$(basename "$(dirname -- "$selector")")" in GE-Proton*|proton-cachyos-slr*) return 1 ;; esac
    readlink -f -- "$(dirname -- "$selector")"
    return 0
  fi
  wanted="$(printf '%s' "${selector##*/}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  [ -n "$wanted" ] || return 1
  while IFS= read -r candidate; do
    name="${candidate##*/}"
    normalized="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
    if [ "$normalized" = "$wanted" ]; then
      case "${candidate##*/}" in GE-Proton*|proton-cachyos-slr*) return 1 ;; esac
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(continuity_proton_roots)
  return 1
}

continuity_steam_root() {
  local root
  if [ -n "${CONTINUITY_STEAM_ROOT:-}" ]; then
    printf '%s\n' "$CONTINUITY_STEAM_ROOT"
    return 0
  fi
  for root in \
    "$XDG_DATA_HOME/Steam" \
    "$HOME/.steam/root" \
    "$HOME/.steam/steam" \
    "$HOME/.local/share/Steam" \
    "/usr/share/steam"; do
    [ -d "$root" ] || continue
    readlink -f -- "$root"
    return 0
  done
  printf '%s/Steam\n' "$XDG_DATA_HOME"
}
