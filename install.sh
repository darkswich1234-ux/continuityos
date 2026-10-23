#!/usr/bin/env bash
# =============================================================================
#  ContinuityOS — unified installer / provisioner
# =============================================================================
#  Turns an Arch Linux machine (or a fresh archiso install) into ContinuityOS:
#  the Universal Windows Compatibility Engine plus the Android-like Hyprland
#  shell, in one idempotent script.
#
#  Quick start:
#      ./install.sh --user                 # configure THIS user on an existing Arch
#      sudo ./install.sh --system          # packages, /etc, hooks, units, session
#      sudo ./install.sh --all --yes       # both (fresh machine / ISO)
#      ./install.sh --all --dry-run        # show every action, change nothing
#
#  Everything it does is reversible by hand: see docs/UNINSTALL.md.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- defaults ----------------------------------------------------------------
MODE=""
DRY_RUN=0
ASSUME_YES=0
SKIP_PACKAGES=0
WITH_AUR=""
WITH_WINBOAT=0
WITH_FREEBUFF=0
GAMING_ONLY=0
NO_ENABLE=0
# Empty means "decide by mode": --system/--all autologin unless told otherwise,
# because the whole point of this OS is that boot goes straight to the desktop.
AUTOLOGIN=""
SRC_DIR="$REPO_DIR"
TARGET_USER="${SUDO_USER:-${USER:-}}"
VERBOSE=0

CONTINUITY_VERSION="0.1.0"
PREFIX_LIB="$REPO_DIR/lib/continuity-common.sh"

usage() {
  cat <<'EOF'
ContinuityOS installer — Universal Windows Compatibility Engine + Android-like shell

USAGE
  ./install.sh [--user | --system | --all] [OPTIONS]

MODES (pick one; default: --user)
  --user            Configure the current user: ~/.config, ~/.local, mime handlers,
                    prefixes, wallpapers, shell widgets. No root needed except for
                    optional package installation.
  --system          Install packages, the continuity-* CLI, /etc files, pacman hooks,
                    systemd units, the Wayland session and system-wide mime defaults.
                    Requires root.
  --all             --system then --user (for the target user).

OPTIONS
  --dry-run              Print every action without performing it.
  -y, --yes              Assume yes for all prompts (needed for unattended runs).
  --skip-packages        Configure only; do not install or remove any package.
  --with-aur             Use/build an AUR helper (yay) and install AUR extras:
                         proton-ge-custom-bin, Heroic, ArtCraft, GearLever, winboat.
  --no-aur               Never touch the AUR, even if a helper is present.
  --with-winboat         Install and enable the WinBoat container bridge for
                         Windows utilities outside Proton's scope.
  --with-freebuff        Install Freebuff (AUR freebuff-bin) — the agent you are
                         running right now has a native Linux build.
  --gaming-only          Skip the creative suite and desktop extras; gaming stack only.
  --user NAME            Target user for --system/--all (default: $SUDO_USER).
  --src DIR              Source tree to install from (default: this repo).
  --autologin            Boot straight into ContinuityOS (the default for --system
                         and --all): greetd starts the session itself, so there is
                         no login prompt and no session chooser, and the greeter
                         appears only after a logout. Undo with continuity-boot off.
  --no-autologin         Keep a login prompt at boot (disables greetd again).
  --no-enable            Copy unit files but do not enable/start services.
  -v, --verbose          Extra output.
  -h, --help             This help.

WHAT THIS SCRIPT TOUCHES
  /usr/local/bin/continuity-*        /usr/local/lib/continuity/continuity-common.sh
  /usr/share/continuity/             /usr/share/applications/continuity-*.desktop
  /usr/share/wayland-sessions/continuity.desktop
  /etc/pacman.d/hooks/9?-continuity-*.hook
  /etc/systemd/system/continuity-*.service
  /usr/lib/systemd/user/continuity-*.service|timer
  /etc/continuity/install.conf       /var/lib/continuity/
  /etc/greetd/config.toml            /etc/systemd/system/greetd.service (enabled)
  $HOME/.config/{continuity,hypr,waybar,eww,rofi,dunst}
  $HOME/.local/share/{universal-prefixes,umu,continuity/assets,applications/continuity}
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --system|--all)
      [ -z "$MODE" ] || { echo "install.sh: only one mode may be given" >&2; exit 2; }
      MODE="${1#--}"; shift ;;
    --user)
      shift
      if [ -n "$MODE" ]; then
        # `--all --user bob`: the mode is settled, so a following name can only
        # mean the target account. The ISO's installer and the docs spell it
        # this way, and refusing it turned a working command into an error.
        [ -n "${1:-}" ] || { echo "install.sh: --user needs a name here (a mode was already given)" >&2; exit 2; }
        [ "${1#-}" = "$1" ] || { echo "install.sh: --user needs a name, got '$1'" >&2; exit 2; }
        TARGET_USER="$1"; shift
      else
        MODE="user"
        if [ -n "${1:-}" ] && [ "${1#-}" = "$1" ]; then TARGET_USER="$1"; shift; fi
      fi
      ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -y|--yes)         ASSUME_YES=1; shift ;;
    --skip-packages)  SKIP_PACKAGES=1; shift ;;
    --with-aur)       WITH_AUR=1; shift ;;
    --no-aur)         WITH_AUR=0; shift ;;
    --with-winboat)   WITH_WINBOAT=1; shift ;;
    --with-freebuff)  WITH_FREEBUFF=1; shift ;;
    --gaming-only)    GAMING_ONLY=1; shift ;;
    --no-enable)      NO_ENABLE=1; shift ;;
    --autologin)      AUTOLOGIN=1; shift ;;
    --no-autologin)   AUTOLOGIN=0; shift ;;
    --target-user)    [ -n "${2:-}" ] || { echo "--target-user needs a name" >&2; exit 2; }; TARGET_USER="$2"; shift 2 ;;
    --src)            [ -n "${2:-}" ] || { echo "--src needs a directory" >&2; exit 2; }; SRC_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -v|--verbose)     VERBOSE=1; shift ;;
    -h|--help|help)   usage; exit 0 ;;
    *) echo "install.sh: unknown option '$1' (see --help)" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || MODE="user"

export ASSUME_YES CONTINUITY_ASSUME_YES="$ASSUME_YES"
[ "$ASSUME_YES" = "1" ] && export CONTINUITY_ASSUME_YES=1

# --- logging / action wrapper ------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YLW=$'\033[33m'; C_BLU=$'\033[34m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_DIM=''; C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_BLD=''
fi
say()    { printf '%s==>%s %s\n' "$C_BLU" "$C_RESET" "$*" >&2; }
ok()     { printf '%s  ok%s %s\n' "$C_GRN" "$C_RESET" "$*" >&2; }
skip()   { printf '%s  --%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2; }
warn()   { printf '%s  !!%s %s\n' "$C_YLW" "$C_RESET" "$*" >&2; }
fail()   { printf '%s error:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()    { fail "$@"; exit 1; }
step()   { printf '\n%s%s%s\n' "$C_BLD" "$*" "$C_RESET" >&2; }

# Every mutating action goes through run()/run_as() so --dry-run is honest.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '  %s+ %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2
    return 0
  fi
  [ "$VERBOSE" = "1" ] && printf '  %s+ %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2
  "$@"
}

# Run a command as the target user when we are root (config files must be owned
# by the human, not by root).
run_as_user() {
  local user="$1"; shift
  if [ "$(id -u)" != "0" ]; then
    run "$@"
    return 0
  fi
  if [ "$user" = "root" ] || [ -z "$user" ]; then
    run "$@"
    return 0
  fi
  if command -v runuser >/dev/null 2>&1; then
    run runuser -u "$user" -- "$@"
  else
    run su -s /bin/bash -c "$(printf '%q ' "$@")" "$user"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }
is_arch() { [ -f /etc/arch-release ] || have pacman; }

# --- shared library (for slugify/paths when helper scripts are not installed) -
if [ -r "$PREFIX_LIB" ]; then
  # shellcheck disable=SC1090
  . "$PREFIX_LIB"
fi

# =============================================================================
#  0. preflight
# =============================================================================
preflight() {
  step "Preflight"
  if is_arch; then
    ok "Arch Linux detected ($(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Arch}"))"
  else
    if [ "$DRY_RUN" = "1" ]; then
      warn "not an Arch system — dry run continues, a real run would stop here"
    else
      die "ContinuityOS targets Arch Linux (pacman not found). See docs/PORTING.md."
    fi
  fi

  if [ "$MODE" = "system" ] || [ "$MODE" = "all" ]; then
    if [ "$(id -u)" != "0" ]; then
      die "--$MODE needs root: sudo $0 --$MODE $( [ "$ASSUME_YES" = 1 ] && echo --yes )"
    fi
    ok "running as root"
  fi

  [ -r "$SRC_DIR/install.sh" ] || die "source tree not found at $SRC_DIR (use --src DIR)"
  local required=(bin/continuity-run bin/continuity-prefix bin/continuity-gaming-mode \
                  bin/continuity-panel bin/continuity-shell \
                  bin/continuity-session-start bin/continuity-wizard lib/continuity-common.sh \
                  config/hypr/hyprland.conf config/waybar/config.jsonc config/eww/eww.yuck)
  local f missing=0
  for f in "${required[@]}"; do
    [ -e "$SRC_DIR/$f" ] || { fail "missing component: $f"; missing=1; }
  done
  [ "$missing" = "0" ] || die "the source tree is incomplete — re-clone it (or run tests/run.sh to see what is wrong)"
  local source_file_count
  source_file_count="$(find "$SRC_DIR" -path "$SRC_DIR/.git" -prune -o -type f -print | wc -l)"
  ok "source tree complete ($source_file_count files)"

  # multilib: Wine and the 32-bit Vulkan stack live there.
  if have pacman && ! grep -qE '^\s*\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    warn "the [multilib] repo is not enabled — 32-bit gaming (Wine and graphics libraries) needs it"
    MULTILIB_NEEDED=1
  fi

  HAVE_HELPER=""
  for h in yay paru; do have "$h" && { HAVE_HELPER="$h"; break; }; done

  if [ -z "$WITH_AUR" ]; then
    if [ -n "$HAVE_HELPER" ]; then WITH_AUR=1; else WITH_AUR=0; fi
  fi
  [ "$WITH_AUR" = "1" ] && [ -z "$HAVE_HELPER" ] && ok "no AUR helper yet — one can be bootstrapped on request"

  # Graphics detection decides which driver list is installed.
  GPU_VENDORS="$(detect_gpus)"
  ok "GPU vendor(s): ${GPU_VENDORS:-unknown}"
  if [ "$(uname -m)" != "x86_64" ]; then
    warn "host architecture is $(uname -m): Proton/umu need x86_64 (FEX-Emu/Box64 on ARM — see docs/ARM.md)"
  fi
}

# lspci is not guaranteed on a minimal install; fall back to sysfs.
detect_gpus() {
  local vendors=""
  if have lspci; then
    vendors="$(lspci 2>/dev/null | awk '/VGA|3D|Display/ {print tolower($0)}' \
      | grep -oE 'nvidia|amd|ati|radeon|intel|virtio|vmware' | sort -u | tr '\n' ' ')"
  fi
  if [ -z "$vendors" ] && [ -d /sys/class/drm ]; then
    local d
    for d in /sys/class/drm/card*/device/vendor; do
      [ -r "$d" ] || continue
      case "$(cat "$d")" in
        0x10de) vendors="$vendors nvidia" ;;
        0x1002) vendors="$vendors amd" ;;
        0x8086) vendors="$vendors intel" ;;
      esac
    done
    vendors="$(printf '%s\n' $vendors | sort -u | tr '\n' ' ')"
  fi
  printf '%s' "${vendors% }"
}

# =============================================================================
#  1. packages
# =============================================================================
read_list() {
  local file="$1"
  [ -r "$file" ] || return 0
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" | grep -v '^$' || true
}

enable_multilib() {
  [ "${MULTILIB_NEEDED:-0}" = "1" ] || return 0
  # --skip-packages means "configure only", and the `pacman -Sy` at the end of
  # this function is a package action. Running it anyway made --skip-packages
  # silently refresh the database on a live medium that cannot reach the repos.
  if [ "$SKIP_PACKAGES" = "1" ]; then
    warn "--skip-packages: leaving /etc/pacman.conf alone. The engine needs [multilib];\n      uncomment it there before installing any lib32-* package"
    return 0
  fi
  say "enabling the [multilib] repository"
  if [ "$DRY_RUN" = "1" ]; then
    printf '  %s+ enable [multilib] in /etc/pacman.conf and pacman -Sy%s\n' "$C_DIM" "$C_RESET" >&2
    return 0
  fi
  cp -a /etc/pacman.conf "/etc/pacman.conf.continuity-backup"
  # Dependency-free edit: either uncomment the stock Arch block, or append one.
  if grep -qE '^[[:space:]]*#[[:space:]]*\[multilib\]' /etc/pacman.conf; then
    sed -i -E '0,/^[[:space:]]*#[[:space:]]*\[multilib\]/s//[multilib]/' /etc/pacman.conf
    sed -i -E '/^\[multilib\]/,/^\[/{s|^[[:space:]]*#[[:space:]]*(Include[[:space:]]*=[[:space:]]*/etc/pacman.d/mirrorlist)|\1|}' /etc/pacman.conf
    ok "/etc/pacman.conf: uncommented [multilib] (backup: /etc/pacman.conf.continuity-backup)"
  else
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
    ok "/etc/pacman.conf: appended [multilib] (backup: /etc/pacman.conf.continuity-backup)"
  fi
  run pacman -Sy --noconfirm
}

pacman_install() {
  local pkgs=("$@")
  [ "${#pkgs[@]}" -gt 0 ] || return 0
  local available=() p
  if have pacman && [ "$DRY_RUN" != "1" ]; then
    for p in "${pkgs[@]}"; do
      if pacman -Si -- "$p" >/dev/null 2>&1; then
        available+=("$p")
      elif pacman -Qq -- "$p" >/dev/null 2>&1; then
        skip "$p (already installed, not in the repos)"
      else
        warn "package not found in the official repos: $p (skipped — it may belong to the AUR)"
      fi
    done
  else
    available=("${pkgs[@]}")
  fi
  [ "${#available[@]}" -gt 0 ] || return 0
  # --needed keeps re-runs fast and non-destructive.
  run pacman -S --needed --noconfirm "${available[@]}"
}

install_packages_system() {
  step "System packages"
  enable_multilib

  local lists=(core desktop)
  [ "$GAMING_ONLY" = "1" ] || lists+=(creative)
  lists+=(gaming)

  local pkgfiles=()
  local l
  for l in "${lists[@]}"; do
    [ -r "$SRC_DIR/packages/$l.list" ] && pkgfiles+=("$SRC_DIR/packages/$l.list")
  done

  if [ "$SKIP_PACKAGES" = "1" ]; then
    skip "--skip-packages: package installation skipped"
  else
    local all=() f
    for f in "${pkgfiles[@]}"; do
      # shellcheck disable=SC2207
      all+=($(read_list "$f"))
    done
    # Deduplicate while keeping the (kernel-first) order stable.
    local dedup=() seen=" " p
    for p in "${all[@]}"; do
      case "$seen" in *" $p "*) continue ;; esac
      seen="$seen$p "; dedup+=("$p")
    done
    say "installing ${#dedup[@]} packages from packages/*.list"
    if [ "${#dedup[@]}" -gt 60 ]; then
      # Big batches are split so a single bad entry cannot abort the whole run.
      local chunk=()
      for p in "${dedup[@]}"; do
        chunk+=("$p")
        if [ "${#chunk[@]}" -ge 40 ]; then pacman_install "${chunk[@]}" || warn "some packages failed"; chunk=(); fi
      done
      [ "${#chunk[@]}" -gt 0 ] && { pacman_install "${chunk[@]}" || warn "some packages failed"; }
    else
      pacman_install "${dedup[@]}" || warn "some packages failed — the shell may be incomplete"
    fi
  fi

  install_graphics 1
}

install_graphics() {
  local system_scope="${1:-0}"
  step "Graphics stack (Vulkan + 32-bit)"
  local common=(vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa lib32-mesa lib32-libgl lib32-vulkan-icd-loader)
  local extra=() layer
  for layer in $GPU_VENDORS; do
    case "$layer" in
      nvidia) extra+=(nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver) ;;
      amd|ati|radeon) extra+=(vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu radeontop) ;;
      intel) extra+=(vulkan-intel lib32-vulkan-intel intel-media-driver) ;;
      *) ;;
    esac
  done
  [ "${#extra[@]}" -gt 0 ] || extra+=(vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel)

  if [ "$system_scope" = "1" ]; then
    if [ "$SKIP_PACKAGES" = "1" ]; then
      skip "--skip-packages: graphics stack not installed"
    else
      say "installing: ${extra[*]}"
      pacman_install "${common[@]}" "${extra[@]}" || warn "some graphics packages failed"
    fi
  fi

  # NVIDIA users need matching 32-bit libs or Proton refuses to start.
  if is_arch && [ "$SKIP_PACKAGES" != "1" ] && [ "$DRY_RUN" != "1" ]; then
    case " $GPU_VENDORS " in
      *" nvidia "*)
        if have pacman && pacman -Qq nvidia-utils >/dev/null 2>&1 && ! pacman -Qq lib32-nvidia-utils >/dev/null 2>&1; then
          warn "NVIDIA detected: lib32-nvidia-utils is missing — 32-bit (Proton) games will not launch"
        fi
        ;;
    esac
  fi

  if [ "$(uname -m)" != "x86_64" ]; then
    warn "non-x86_64 host: install FEX-Emu/Box64 yourself and expect Proton performance limits (docs/ARM.md)"
  fi
}

install_aur() {
  [ "$WITH_AUR" = "1" ] || return 0
  [ "$SKIP_PACKAGES" = "1" ] && { skip "--skip-packages: AUR extras not installed"; return 0; }
  step "AUR extras"
  local helper="$HAVE_HELPER"
  if [ -z "$helper" ]; then
    if [ "$ASSUME_YES" != "1" ] && [ -t 0 ]; then
      printf 'Bootstrap the yay AUR helper (needed for GE-Proton, Heroic, ArtCraft, GearLever)? [y/N] ' >&2
      read -r reply || reply=n
      case "$reply" in [yY]*) ;; *) skip "AUR extras skipped (no helper)"; return 0 ;; esac
    elif [ "$ASSUME_YES" != "1" ]; then
      skip "AUR extras need a helper (yay/paru); run with --with-aur in an interactive shell"
      return 0
    fi
    continuity_bootstrap_yay || { warn "could not bootstrap yay; AUR extras skipped"; return 0; }
    helper="yay"
  fi

  local wanted=()
  local f="$SRC_DIR/packages/aur.list"
  if [ -r "$f" ]; then
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      case "$entry" in
        winboat*) [ "$WITH_WINBOAT" = "1" ] || continue ;;
        freebuff*) [ "$WITH_FREEBUFF" = "1" ] || continue ;;
      esac
      if [ "$GAMING_ONLY" = "1" ]; then
        case "$entry" in
          photocraft|filmcraft-git|gearlever) continue ;;
        esac
      fi
      wanted+=("$entry")
    done < <(read_list "$f")
  fi
  [ "${#wanted[@]}" -gt 0 ] || { skip "nothing to install from the AUR"; return 0; }

  local p failed_aur=()
  say "installing from the AUR: ${wanted[*]}"
  for p in "${wanted[@]}"; do
    if run "$helper" -S --needed --noconfirm -- "$p"; then
      ok "AUR: $p"
    else
      failed_aur+=("$p")
      warn "AUR package failed (continuing): $p"
    fi
  done
  if [ "${#failed_aur[@]}" -gt 0 ]; then
    warn "these AUR packages were not installed: ${failed_aur[*]}"
    warn "try 'yay -S ${failed_aur[*]}' by hand; AUR builds can fail on missing build deps"
  fi
}

# Build yay from the AUR without an existing helper (the standard bootstrap).
continuity_bootstrap_yay() {
  say "bootstrapping yay (build user: ${TARGET_USER:-root})"
  local tmp
  tmp="$(mktemp -d)" || return 1
  if ! run_as_user "$TARGET_USER" git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"; then
    rm -rf "$tmp"; return 1
  fi
  ( cd "$tmp/yay-bin" && run_as_user "$TARGET_USER" makepkg -si --noconfirm )
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

install_flatpak_extras() {
  [ "$SKIP_PACKAGES" = "1" ] && return 0
  step "Flatpak extras (GearLever, containers)"
  if ! have flatpak; then
    warn "flatpak is not installed; skipping GearLever (install with: sudo pacman -S flatpak)"
    return 0
  fi
  run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
  # GearLever is the AppImage manager: double-click-friendly AppImage integration.
  if ! run flatpak install -y --user flathub it.mijorus.gearlever; then
    warn "GearLever install failed — install it later with: flatpak install --user flathub it.mijorus.gearlever"
  fi
  if [ "$GAMING_ONLY" != "1" ]; then
    # Bottles gives a friendly GUI for the Wine side of the compatibility engine.
    run flatpak install -y --user flathub com.usebottles.bottles || \
      warn "Bottles not installed (optional)"
  fi
}

# =============================================================================
#  2. system deployment (/etc, units, hooks, session, mime)
# =============================================================================
install_system_files() {
  step "System files"

  run install -d -m 0755 /usr/local/bin /usr/local/lib/continuity /usr/share/continuity
  run install -d -m 0755 /usr/share/continuity/config
  run install -d -m 0755 /usr/share/applications /usr/share/wayland-sessions
  run install -d -m 0755 /etc/pacman.d/hooks /etc/continuity
  run install -d -m 0755 /usr/lib/systemd/user /var/lib/continuity

  # --- the CLI ---------------------------------------------------------------
  local s
  for s in continuity-run continuity-prefix continuity-gaming-mode \
           continuity-panel continuity-shell continuity-session-start continuity-screenshot \
           continuity-wizard continuity-first-boot continuity-boot continuity-region \
           continuity-export continuity-shakedown continuity-end4-pc; do
    [ -r "$SRC_DIR/bin/$s" ] || { warn "bin/$s is missing from the source tree"; continue; }
    run install -m 0755 "$SRC_DIR/bin/$s" "/usr/local/bin/$s"
  done
  run install -m 0644 "$SRC_DIR/lib/continuity-common.sh" /usr/local/lib/continuity/continuity-common.sh

  # --- desktop entries & session --------------------------------------------
  local d
  for d in "$SRC_DIR"/desktop/*.desktop; do
    [ -e "$d" ] || continue
    run install -m 0644 "$d" "/usr/share/applications/$(basename "$d")"
  done
  [ -r "$SRC_DIR/sessions/continuity.desktop" ] && \
    run install -m 0644 "$SRC_DIR/sessions/continuity.desktop" /usr/share/wayland-sessions/continuity.desktop

  # --- system mime defaults --------------------------------------------------
  if [ -r "$SRC_DIR/desktop/mimeapps.list" ]; then
    run install -d -m 0755 /etc/xdg
    run install -m 0644 "$SRC_DIR/desktop/mimeapps.list" /etc/xdg/mimeapps.list
  fi

  # --- defaults for new users (skel) ----------------------------------------
  run install -d -m 0755 /etc/skel/.config/continuity
  [ -r "$SRC_DIR/config/continuity/environment.conf" ] && \
    run install -m 0644 "$SRC_DIR/config/continuity/environment.conf" /etc/skel/.config/continuity/environment.conf
  run install -d -m 0755 /usr/share/continuity/config
  run cp -a "$SRC_DIR/config/." /usr/share/continuity/config/

  # --- pacman hooks ----------------------------------------------------------
  local h
  for h in "$SRC_DIR"/pacman/hooks/*.hook; do
    [ -e "$h" ] || continue
    case "$(basename "$h")" in 99-continuity-umu.hook) continue ;; esac
    run install -m 0644 "$h" "/etc/pacman.d/hooks/$(basename "$h")"
  done

  # --- systemd units --------------------------------------------------------
  local u
  for u in "$SRC_DIR"/systemd/*.service "$SRC_DIR"/systemd/*.timer; do
    [ -e "$u" ] || continue
    case "$(basename "$u")" in
      # Legacy UMU runtime support is not installed with the host Proton engine.
      continuity-umu-seed.service|continuity-umu-verify.service|continuity-umu-verify.timer)
        continue ;;
      *)
        run install -m 0644 "$u" "/etc/systemd/system/$(basename "$u")" ;;
    esac
  done

  # --- optional WinBoat drop-in ---------------------------------------------
  if [ "$WITH_WINBOAT" = "1" ]; then
    say "WinBoat bridge requested"
    if have winboat; then
      ok "winboat found"
      [ "$NO_ENABLE" = "1" ] || run systemctl enable continuity-winboat.service
    else
      warn "winboat is not installed yet — the service stays inactive until it is"
    fi
  fi

  # --- icons into the hicolor theme ----------------------------------------
  # Generated launchers point at the absolute asset path, but the shell's own
  # entries use theme names (continuity-windows, windows-app, input-gaming,
  # video-display), so those need a system theme to resolve.
  run install -d -m 0755 /usr/share/icons/hicolor/scalable/apps
  if [ -d "$SRC_DIR/assets/icons" ]; then
    local ic
    for ic in "$SRC_DIR"/assets/icons/*.svg; do
      [ -e "$ic" ] || continue
      run install -m 0644 "$ic" "/usr/share/icons/hicolor/scalable/apps/$(basename "$ic")"
    done
  fi

  # --- wallpapers: hyprpaper reads PNG reliably, so convert the SVGs --------
  local wp
  if have rsvg-convert; then
    run install -d -m 0755 /usr/share/backgrounds/continuity
    for wp in "$SRC_DIR"/assets/wallpapers/*.svg; do
      [ -e "$wp" ] || continue
      run rsvg-convert -w 3840 -h 2160 "$wp" -o "/usr/share/backgrounds/continuity/$(basename "${wp%.svg}").png"
    done
  else
    warn "librsvg (rsvg-convert) not installed — wallpapers stay SVG (install librsvg if they do not show)"
  fi

  # --- first-boot unit enablement -------------------------------------------
  if [ "$NO_ENABLE" != "1" ] && have systemctl; then
    run systemctl daemon-reload || true
    run systemctl enable continuity-first-boot.service || true
  fi

  # --- install.conf: what the ISO / unattended installs read ----------------
  if [ -r "$SRC_DIR/etc/install.conf" ]; then
    run install -m 0644 "$SRC_DIR/etc/install.conf" /etc/continuity/install.conf
  fi
  if [ "$DRY_RUN" != "1" ]; then
    # Never clobber the shipped defaults (systemd reads this file as an
    # EnvironmentFile); update our keys in place and append what is missing.
    set_conf_key() {
      local key="$1" value="$2" file=/etc/continuity/install.conf
      if grep -qE "^[[:space:]]*${key}=" "$file" 2>/dev/null; then
        sed -i -E "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file"
      else
        printf '%s=%s\n' "$key" "$value" >>"$file"
      fi
    }
    [ -e /etc/continuity/install.conf ] || : >/etc/continuity/install.conf
    set_conf_key CONTINUITY_SOURCE_DIR "$SRC_DIR"
    set_conf_key CONTINUITY_VERSION "$CONTINUITY_VERSION"
    set_conf_key CONTINUITY_TARGET_USER "${TARGET_USER:-}"
    set_conf_key CONTINUITY_GAMING_ONLY "$GAMING_ONLY"
    set_conf_key CONTINUITY_WITH_WINBOAT "$WITH_WINBOAT"
    # Recorded so first-boot work and `continuity-boot doctor` can tell what this
    # machine was asked to do, rather than inferring it from greetd's state.
    local autologin_effective=1
    if [ "$AUTOLOGIN" = "0" ] || [ "$NO_ENABLE" = "1" ]; then autologin_effective=0; fi
    set_conf_key CONTINUITY_AUTOLOGIN "$autologin_effective"
    chmod 0644 /etc/continuity/install.conf
    ok "/etc/continuity/install.conf updated"
  fi

  # --- documentation (referenced by /etc/motd.d/continuity) -----------------
  run install -d -m 0755 /usr/share/doc/continuity
  if [ -d "$SRC_DIR/docs" ]; then
    while IFS= read -r -d '' f; do
      run install -m 0644 "$f" "/usr/share/doc/continuity/$(basename "$f")"
    done < <(find "$SRC_DIR/docs" -maxdepth 1 -type f -name '*.md' -print0)
  fi
  [ -r "$SRC_DIR/README.md" ] && run install -m 0644 "$SRC_DIR/README.md" /usr/share/doc/continuity/README.md

  # --- systemd drop-ins shipped with the ISO profile ------------------------
  # Only present in an ISO-built tree; a git checkout has nothing here and this
  # loop is a no-op.
  if [ -d "$SRC_DIR/iso/profile/airootfs/etc/systemd/system" ]; then
    while IFS= read -r -d '' f; do
      local rel="${f#"$SRC_DIR/iso/profile/airootfs/etc/systemd/system/"}"
      case "$rel" in
        # The live medium's own files are meaningless (and worse: greetd's drop-in
        # orders it after continuity-live-boot.service, a unit that only exists on
        # the medium) once the system is installed. Match on the path, not the
        # basename: a drop-in's basename says 10-continuity-live.conf, not
        # *live-boot*, so the old rule let it through onto real machines.
        *live*) skip "live-medium file not installed: $rel"; continue ;;
      esac
      run install -d -m 0755 "/etc/systemd/system/$(dirname "$rel")"
      run install -m 0644 "$f" "/etc/systemd/system/$rel"
    done < <(find "$SRC_DIR/iso/profile/airootfs/etc/systemd/system" -type f -print0)
  fi

  # --- uninstall helper lands next to the code it removes -------------------
  if [ -r "$SRC_DIR/tools/uninstall.sh" ]; then
    run install -m 0755 "$SRC_DIR/tools/uninstall.sh" /usr/local/bin/continuity-uninstall
  fi

  # Desktop database refresh so the new entries appear immediately.
  have update-desktop-database && run update-desktop-database -q /usr/share/applications || true
  have update-mime-database && run update-mime-database /usr/share/mime || true
  have gtk-update-icon-cache && run gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
  have fc-cache && run fc-cache -f >/dev/null 2>&1 || true
  ok "system files installed"
}

# =============================================================================
#  3. boot experience (no login prompt, no session chooser)
# =============================================================================
# A stock Arch install gives you a TTY login and then a session chooser, which
# is `Arch -> Hyprland -> ContinuityOS`: two steps before anything works. This
# removes both by handing the boot path to greetd's [initial_session].
#
# It is delegated to continuity-boot rather than done here with sed because that
# tool refuses to write a configuration that could leave a machine with no way
# in (missing session binary, nonexistent account, root autologin, a second
# display manager already owning the seat). A broken autologin is the one
# mistake you cannot fix from the desktop you cannot reach.
boot_tool() {
  if [ -x /usr/local/bin/continuity-boot ]; then printf '%s\n' /usr/local/bin/continuity-boot
  elif [ -x "$SRC_DIR/bin/continuity-boot" ]; then printf '%s\n' "$SRC_DIR/bin/continuity-boot"
  else return 1
  fi
}

install_boot_experience() {
  step "Boot"

  local tool target="${TARGET_USER:-}"
  local want_autologin=1
  if [ "$AUTOLOGIN" = "0" ] || [ "$NO_ENABLE" = "1" ]; then want_autologin=0; fi

  if ! have systemctl; then
    warn "systemd is not running here — the boot path was left alone"
    return 0
  fi

  if ! tool="$(boot_tool)"; then
    warn "continuity-boot is not available, so the boot path was left alone"
    return 0
  fi

  local args=()
  if [ "$DRY_RUN" = "1" ]; then args+=(--dry-run); fi

  if [ "$want_autologin" = "1" ]; then
    case "$target" in
      ""|root)
        warn "no target user to log in as — autologin not configured"
        warn "  finish it yourself with: sudo continuity-boot on --user <name>"
        return 0
        ;;
    esac
    args+=(--user "$target")
    if "$tool" on "${args[@]}"; then
      ok "this machine now boots straight into ContinuityOS as '$target'"
    else
      warn "autologin was NOT configured — you will still meet a login prompt"
      warn "  finish it by hand with: sudo continuity-boot on --user $target"
      warn "  see what is wrong with:  sudo continuity-boot doctor"
    fi
  else
    if "$tool" off "${args[@]}"; then
      case "${AUTOLOGIN}" in
        0) ok "a login prompt is kept at boot, as asked (--no-autologin)" ;;
        *) ok "services not enabled (--no-enable), so the boot path is untouched" ;;
      esac
    else
      warn "could not adjust the boot path — see: sudo continuity-boot status"
    fi
  fi
}

# =============================================================================
#  4. user deployment
# =============================================================================
install_user_files() {
  step "User configuration"
  local user="$TARGET_USER"
  local home

  if [ "$(id -u)" = "0" ]; then
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)"
    [ -n "$home" ] || die "cannot resolve the home directory of '$user' (pass --user NAME)"
  else
    user="$(id -un)"
    home="$HOME"
  fi
  [ -d "$home" ] || die "home directory does not exist: $home"
  ok "target user: $user ($home)"

  # --- config trees ---------------------------------------------------------
  local rel
  for rel in continuity hypr waybar eww rofi dunst gtk-3.0 gtk-4.0; do
    [ -d "$SRC_DIR/config/$rel" ] || continue
    run install -d -m 0755 "$home/.config/$rel"
    while IFS= read -r -d '' f; do
      local dest="$home/.config/${f#"$SRC_DIR/config/"}"
      run install -d -m 0755 "$(dirname "$dest")"
      run install -m 0644 "$f" "$dest"
    done < <(find "$SRC_DIR/config/$rel" -type f -print0)
  done

  # Widget scripts must be executable or Eww/Waybar fail at spawn time.
  if [ -d "$home/.config/eww/scripts" ]; then
    while IFS= read -r -d '' f; do
      run chmod 0755 "$f"
    done < <(find "$home/.config/eww/scripts" -type f -name '*.sh' -print0)
  fi

  # The same GTK stylesheet drives GTK3 and GTK4 apps (both load ~/.config/gtk-N/gtk.css).
  if [ -r "$SRC_DIR/config/continuity/gtk.css" ]; then
    run install -d -m 0755 "$home/.config/gtk-3.0" "$home/.config/gtk-4.0"
    run install -m 0644 "$SRC_DIR/config/continuity/gtk.css" "$home/.config/gtk-3.0/gtk.css"
    run install -m 0644 "$SRC_DIR/config/continuity/gtk.css" "$home/.config/gtk-4.0/gtk.css"
  fi

  # --- runtime directories --------------------------------------------------
  run install -d -m 0700 "$home/.local/share/universal-prefixes"
  run install -d -m 0755 "$home/.local/share/continuity/assets/wallpapers"
  run install -d -m 0755 "$home/.local/share/continuity/assets/icons"
  run install -d -m 0755 "$home/.local/state/continuity"
  run install -d -m 0755 "$home/.local/share/applications/continuity"

  # --- environment.conf (never clobber the user's own edits) ---------------
  local envconf="$home/.config/continuity/environment.conf"
  if [ "$DRY_RUN" != "1" ] && [ -e "$envconf" ] && [ -r "$SRC_DIR/config/continuity/environment.conf" ]; then
    if ! cmp -s "$envconf" "$SRC_DIR/config/continuity/environment.conf"; then
      cp -a "$envconf" "$envconf.continuity-backup" 2>/dev/null || true
      if [ "${CONTINUITY_KEEP_ENV:-0}" = "1" ]; then
        skip "kept existing environment.conf (backup: environment.conf.continuity-backup)"
      else
        install -m 0644 "$SRC_DIR/config/continuity/environment.conf" "$envconf"
        ok "refreshed environment.conf (previous version kept as .continuity-backup)"
      fi
    fi
  fi

  # --- assets (icons ship with the repo; wallpapers converted to PNG) ------
  if [ -d "$SRC_DIR/assets/icons" ]; then
    while IFS= read -r -d '' f; do
      run install -m 0644 "$f" "$home/.local/share/continuity/assets/icons/$(basename "$f")"
    done < <(find "$SRC_DIR/assets/icons" -type f -name '*.svg' -print0)
  fi
  local wp ok_wp=0
  for wp in "$SRC_DIR"/assets/wallpapers/*.svg; do
    [ -e "$wp" ] || continue
    local name; name="$(basename "${wp%.svg}")"
    if have rsvg-convert; then
      run_as_user "$user" rsvg-convert -w 3840 -h 2160 "$wp" -o "$home/.local/share/continuity/assets/wallpapers/$name.png"
    else
      run install -m 0644 "$wp" "$home/.local/share/continuity/assets/wallpapers/$(basename "$wp")"
    fi
    ok_wp=$((ok_wp+1))
  done
  [ "$ok_wp" -gt 0 ] && ok "$ok_wp wallpaper(s) installed"

  # --- permissions must belong to the human ---------------------------------
  if [ "$(id -u)" = "0" ]; then
    run chown -R "$user:$(id -gn "$user" 2>/dev/null || echo "$user")" "$home/.config/continuity" \
      "$home/.config/hypr" "$home/.config/waybar" "$home/.config/eww" "$home/.config/rofi" \
      "$home/.config/dunst" "$home/.local/share/continuity" "$home/.local/state/continuity" \
      "$home/.local/share/universal-prefixes" 2>/dev/null || true
  fi

  # --- mime handlers for Windows executables --------------------------------
  register_mime_handlers "$user" "$home"

  ok "user configuration installed"
}

register_mime_handlers() {
  local user="$1" home="$2"
  step "Registering .exe handlers (Universal Compatibility Engine)"

  # The MIME types a Windows binary can carry. `xdg-mime query filetype` decides
  # which one a double-click reports, so we claim all of them.
  local types=(
    application/x-ms-dos-executable
    application/x-msdownload
    application/x-ms-shortcut
    application/vnd.microsoft.portable-executable
    application/x-msi
  )

  if [ "$(id -u)" = "0" ]; then
    # Write the user's mimeapps.list by hand: xdg-mime would apply it to root.
    local file="$home/.config/mimeapps.list"
    run install -d -m 0755 "$home/.config"
    if [ "$DRY_RUN" = "1" ]; then
      printf '  %s+ associate %d mime types with continuity-wine.desktop in %s%s\n' "$C_DIM" "${#types[@]}" "$file" "$C_RESET" >&2
    elif have python3; then
      touch "$file"
      python3 - "$file" "${types[@]}" <<'PY'
import sys
path, types = sys.argv[1], sys.argv[2:]
key = "continuity-wine.desktop"
section = "[Default Applications]"
try:
    text = open(path).read()
except FileNotFoundError:
    text = ""
lines = [l for l in text.splitlines() if not any(l.startswith(t + "=") for t in types)]
while lines and not lines[-1].strip():
    lines.pop()
if section not in lines:
    if lines:
        lines.append("")
    lines.append(section)
idx = lines.index(section) + 1
for t in reversed(types):
    lines.insert(idx, f"{t}={key}")
open(path, "w").write("\n".join(lines).rstrip() + "\n")
print(f"  ok  {path}: {len(types)} mime types -> {key}")
PY
    else
      # No python: appending a second [Default Applications] section is legal and
      # later keys win, so this still works.
      {
        printf '\n[Default Applications]\n'
        for t in "${types[@]}"; do printf '%s=continuity-wine.desktop\n' "$t"; done
      } >>"$file"
      warn "python3 missing: appended mime associations (duplicates are harmless)"
    fi
    run chown "$user" "$home/.config/mimeapps.list" 2>/dev/null || true
  else
    for t in "${types[@]}"; do
      if have xdg-mime; then
        run xdg-mime default continuity-wine.desktop "$t" || \
          warn "could not set the default handler for $t"
      fi
    done
  fi

  # A user-level desktop entry too, so the association survives even if the
  # system copy is missing (portable/per-user installs).
  local entry="$home/.local/share/applications/continuity-wine.desktop"
  run install -d -m 0755 "$home/.local/share/applications"
  [ -r "$SRC_DIR/desktop/continuity-wine.desktop" ] && \
    run install -m 0644 "$SRC_DIR/desktop/continuity-wine.desktop" "$entry"
  if [ "$DRY_RUN" != "1" ]; then
    have update-desktop-database && run_as_user "$user" update-desktop-database -q "$home/.local/share/applications" || true
  fi

  # Report what a double-click will actually do — the whole point of this step.
  if [ "$DRY_RUN" != "1" ] && have xdg-mime && [ "$(id -u)" != "0" ]; then
    local t resolved
    for t in "${types[@]}"; do
      resolved="$(xdg-mime query default "$t" 2>/dev/null || true)"
      [ -n "$resolved" ] && ok "$t -> $resolved"
    done
  fi
  ok "Windows executable handler registered"
}

# =============================================================================
#  4. optional extras
# =============================================================================
install_freebuff() {
  [ "$WITH_FREEBUFF" = "1" ] || return 0
  step "Freebuff (the agent running this installer has a native Linux build)"
  if have freebuff; then
    ok "freebuff is already installed: $(command -v freebuff)"
    return 0
  fi
  if [ "$SKIP_PACKAGES" = "1" ]; then
    skip "--skip-packages: Freebuff not installed"
    return 0
  fi
  # AUR freebuff-bin is the supported Arch route; it also runs on aarch64.
  local helper="$HAVE_HELPER"
  if [ -z "$helper" ] && [ "$WITH_AUR" = "1" ]; then
    continuity_bootstrap_yay && helper="yay" || true
  fi
  if [ -n "$helper" ]; then
    if run "$helper" -S --needed --noconfirm -- freebuff-bin; then
      ok "freebuff-bin installed — run 'freebuff' in a terminal"
      return 0
    fi
  fi
  warn "could not install freebuff-bin automatically"
  warn "  AUR:        yay -S freebuff-bin"
  warn "  AppImage:   https://freebuff.com  (drag it into GearLever, or run it directly)"
  warn "  Web:        https://freebuff.com  works in any browser today"
}

install_winboat() {
  [ "$WITH_WINBOAT" = "1" ] || return 0
  step "WinBoat (Windows utilities outside Proton's scope)"
  if have winboat; then
    ok "winboat present — enable the bridge with: sudo systemctl enable --now continuity-winboat.service"
    return 0
  fi
  if [ "$SKIP_PACKAGES" = "1" ]; then
    skip "--skip-packages: WinBoat not installed"
    return 0
  fi
  warn "WinBoat ships as an AppImage/deb, not an Arch package — install it from its releases page"
  warn "  then re-run: sudo ./install.sh --system --with-winboat"
  warn "  (the container backend it needs: sudo pacman -S docker && sudo systemctl enable --now docker)"
}

print_summary() {
  step "Done"

  # The boot line is the first thing anybody notices, so it reports what this
  # machine will actually do rather than what the default is.
  local boot_line
  if [ "$MODE" = "user" ]; then
    boot_line='Shell:           log in, then run continuity-shell (pick "ContinuityOS"
                   at the login screen if a display manager is running)'
  elif [ "$AUTOLOGIN" = "0" ] || [ "$NO_ENABLE" = "1" ]; then
    boot_line='Boot:            a login prompt, as you asked. When you want the
                   desktop straight away: sudo continuity-boot on --user <name>'
  else
    boot_line='Boot:            straight into ContinuityOS — no login prompt and no
                   session chooser; the greeter only appears after a logout.
                   Undo with: sudo continuity-boot off'
  fi

  cat >&2 <<EOF
  Mode:            --$MODE$([ "$DRY_RUN" = 1 ] && echo ' (dry run — nothing changed)')
  Windows engine:  double-click any .exe -> continuity-run -> host Proton
                   prefixes in ${CONTINUITY_PREFIX_ROOT:-~/.local/share/universal-prefixes}/<app>/drive_c
  $boot_line
  Gaming mode:     Super+G, or: continuity-gaming-mode toggle
  Quick settings:  Super+W, or: continuity-panel toggle drawer

  First things to try:
    continuity-shakedown                                  # will games run on this box?
    continuity-run --print-env ~/Downloads/anything.exe    # show the resolved env
    continuity-prefix list                                 # what is installed
    continuity-run --print-env <file.exe>                  # inspect host Proton selection
    continuity-end4-pc status|install|launch                # optional pinned Quickshell overlay
    continuity-region show                                 # locale, keymap, timezone, Wi-Fi
    continuity-export export --out ~/setup.tar.zst         # carry all of it to another PC
    continuity-panel status                                # shell surfaces

  Documentation: docs/ARCHITECTURE.md, docs/BOOT.md, docs/COMPATIBILITY.md, docs/FREEBUFF.md
EOF
  # linux-zen is installed but deliberately does not become the boot default on an
  # existing system, so say so rather than leaving a silent no-op.
  if [ "$MODE" != "user" ] && [ "$SKIP_PACKAGES" != "1" ]; then
    case "$(uname -r)" in
      *-zen) ok "running the linux-zen kernel" ;;
      *)
        if have pacman && pacman -Qq linux-zen >/dev/null 2>&1; then
          warn "linux-zen is installed but you are running $(uname -r) — select
      'Arch Linux (linux-zen)' in your bootloader, then reboot to get it"
        fi
        ;;
    esac
  fi
  if [ "$DRY_RUN" = "1" ]; then
    warn "This was a dry run. Re-run without --dry-run to apply."
  fi
}

# =============================================================================
#  main
# =============================================================================
printf '%sContinuityOS installer%s v%s  (repo: %s)\n' "$C_BLD" "$C_RESET" "$CONTINUITY_VERSION" "$SRC_DIR" >&2

preflight

case "$MODE" in
  system)
    install_packages_system
    install_aur
    install_flatpak_extras
    install_freebuff
    install_winboat
    install_system_files
    install_boot_experience
    ;;
  user)
    install_flatpak_extras
    install_freebuff
    install_user_files
    ;;
  all)
    install_packages_system
    install_aur
    install_flatpak_extras
    install_freebuff
    install_winboat
    install_system_files
    install_user_files
    # Last, so the autologin target's session binary and config tree are both
    # already in place when continuity-boot validates the chain.
    install_boot_experience
    ;;
esac

print_summary
