#!/usr/bin/env bash
# ContinuityOS — uninstaller.
#
# Removes everything install.sh put on the machine, and nothing else. Your
# Windows prefixes and the Steam Linux Runtime are only deleted when you ask for
# it explicitly, because they are your data, not the installer's.
#
#   sudo continuity-uninstall --system          remove system files
#   continuity-uninstall --user                 remove this user's ContinuityOS config
#   sudo continuity-uninstall --all             both (user = the invoking user)
#   sudo continuity-uninstall --all --purge-data
#                                               also delete ~/.local/share/universal-prefixes
#                                               and ~/.local/share/umu
#   continuity-uninstall --dry-run --all        show what would be removed
#
# Packages are never removed automatically: many of them (pipewire, networkmanager,
# the graphics stack) are used by the rest of the system. See docs/UNINSTALL.md.
set -euo pipefail

DRY_RUN=0
DO_SYSTEM=0
DO_USER=0
PURGE_DATA=0
ASSUME_YES=0
TARGET_USER="${SUDO_USER:-$(id -un)}"

usage() {
  cat <<'EOF'
continuity-uninstall — remove ContinuityOS from this machine

USAGE
  sudo continuity-uninstall [--system] [--user [NAME]] [--all] [OPTIONS]

OPTIONS
  --system           Remove /usr/local/bin/continuity-*, /usr/local/lib/continuity,
                     /usr/share/continuity, ContinuityOS desktop entries, the Wayland
                     session, /etc/xdg/mimeapps.list entries, pacman hooks, systemd
                     units, /etc/continuity, /var/lib/continuity. Needs root.
  --user [NAME]      Remove ~/.config/{continuity,hypr,waybar,eww,rofi,dunst},
                     ~/.config/gtk-{3,4}.0/{gtk.css,settings.ini}, generated launchers,
                     the xdg-mime associations and this user's state directory.
                     Defaults to $SUDO_USER or the current user.
  --all              --system plus --user.
  --purge-data       Also delete ~/.local/share/universal-prefixes (your Windows apps
                     and their save data!) and ~/.local/share/umu (the Steam Linux
                     Runtime, several GB that would otherwise be re-downloaded).
  --dry-run          Print what would be removed, change nothing.
  -y, --yes          Do not prompt.
  -h, --help         This help.

RESTORING BACKUPS
  /etc/pacman.conf.continuity-backup                  (if multilib was enabled for you)
  ~/.config/continuity/environment.conf.continuity-backup   (your previous settings)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --system) DO_SYSTEM=1; shift ;;
    --user)
      DO_USER=1; shift
      if [ -n "${1:-}" ] && [ "${1#-}" = "$1" ]; then TARGET_USER="$1"; shift; fi
      ;;
    --all) DO_SYSTEM=1; DO_USER=1; shift ;;
    --purge-data) PURGE_DATA=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "continuity-uninstall: unknown option '$1'" >&2; exit 2 ;;
  esac
done

if [ "$DO_SYSTEM" = "0" ] && [ "$DO_USER" = "0" ]; then
  usage >&2
  exit 2
fi

if [ -t 2 ]; then C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_RED=$'\033[31m'
else C_RESET=''; C_DIM=''; C_GRN=''; C_YLW=''; C_RED=''; fi

say()  { printf '%s  --%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2; }
ok()   { printf '%s  ok%s %s\n' "$C_GRN" "$C_RESET" "$*" >&2; }
warn() { printf '%s  !!%s %s\n' "$C_YLW" "$C_RESET" "$*" >&2; }

rm_path() {
  local path="$1"
  [ -e "$path" ] || [ -L "$path" ] || return 1
  if [ "$DRY_RUN" = "1" ]; then say "rm -rf $path"; return 0; fi
  rm -rf -- "$path" && ok "removed $path" || warn "could not remove $path"
}

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  [ -t 0 ] || return 1
  local reply
  printf '%s [y/N] ' "$1" >&2
  read -r reply
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# system
# ---------------------------------------------------------------------------
uninstall_system() {
  [ "$(id -u)" = "0" ] || { warn "--system needs root"; return 1; }
  printf 'Removing system-wide ContinuityOS files%s\n' "$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')" >&2

  # services first, so nothing re-creates files behind us
  if [ "$DRY_RUN" != "1" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now continuity-first-boot.service 2>/dev/null || true
    systemctl disable --now continuity-winboat.service 2>/dev/null || true
    systemctl --global disable continuity-umu-seed.service continuity-umu-verify.timer 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
  fi

  # Stop booting into a session we are about to delete. `continuity-boot off`
  # strips greetd's autologin and re-enables a TTY login, which is exactly the
  # state you want to be in when the session binary disappears a moment later:
  # an autologin pointing at a deleted file is a login loop.
  if [ -x /usr/local/bin/continuity-boot ]; then
    if [ "$DRY_RUN" = "1" ]; then
      say "continuity-boot off (before the session binary is removed)"
    else
      /usr/local/bin/continuity-boot off >/dev/null 2>&1 || \
        warn "continuity-boot off did not complete — check 'continuity-boot status'"
    fi
  fi

  local f
  for f in /usr/local/bin/continuity-run /usr/local/bin/continuity-prefix \
           /usr/local/bin/continuity-gaming-mode /usr/local/bin/continuity-umu-verify \
           /usr/local/bin/continuity-panel /usr/local/bin/continuity-shell \
           /usr/local/bin/continuity-session-start /usr/local/bin/continuity-screenshot \
           /usr/local/bin/continuity-first-boot /usr/local/bin/continuity-uninstall \
           /usr/local/bin/continuity-wizard /usr/local/bin/continuity-boot \
           /usr/local/bin/continuity-region /usr/local/bin/continuity-export \
           /usr/local/bin/continuity-shakedown /usr/local/bin/continuity-end4-pc; do
    rm_path "$f" || true
  done
  rm_path /usr/local/lib/continuity || true
  rm_path /usr/share/continuity || true
  rm_path /usr/share/backgrounds/continuity || true

  for f in /usr/share/applications/continuity-*.desktop /usr/share/wayland-sessions/continuity.desktop; do
    rm_path "$f" || true
  done

  for f in /etc/pacman.d/hooks/98-continuity-desktop-db.hook /etc/pacman.d/hooks/99-continuity-umu.hook; do
    rm_path "$f" || true
  done

  for f in /etc/systemd/system/continuity-*.service /usr/lib/systemd/user/continuity-*.service \
           /usr/lib/systemd/user/continuity-*.timer; do
    rm_path "$f" || true
  done

  # Only ever present if an older install copied the live medium's drop-in onto
  # a real machine (install.sh skips it now): it orders greetd after a unit that
  # does not exist here.
  rm_path /etc/systemd/system/greetd.service.d/10-continuity-live.conf || true

  # mime defaults: drop our keys from the system association file, keep the rest
  if [ -f /etc/xdg/mimeapps.list ]; then
    if [ "$DRY_RUN" = "1" ]; then
      say "strip continuity-wine.desktop keys from /etc/xdg/mimeapps.list"
    else
      sed -i '/continuity-wine\.desktop/d' /etc/xdg/mimeapps.list
      ok "cleaned /etc/xdg/mimeapps.list"
    fi
  fi

  rm_path /etc/skel/.config/continuity || true
  rm_path /etc/continuity || true
  rm_path /var/lib/continuity || true
  rm_path /etc/motd.d/continuity || true

  if [ "$DRY_RUN" != "1" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null || true
    command -v update-mime-database >/dev/null 2>&1 && update-mime-database /usr/share/mime 2>/dev/null || true
  fi

  if [ -e /etc/pacman.conf.continuity-backup ]; then
    warn "a pacman.conf backup from the multilib step is at /etc/pacman.conf.continuity-backup"
  fi
}

# ---------------------------------------------------------------------------
# user
# ---------------------------------------------------------------------------
uninstall_user() {
  local user="$TARGET_USER" home
  if [ "$(id -u)" = "0" ]; then
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)"
  else
    user="$(id -un)"; home="$HOME"
  fi
  [ -n "$home" ] && [ -d "$home" ] || { warn "cannot resolve the home directory of '$user'"; return 1; }

  printf 'Removing ContinuityOS files for %s (%s)%s\n' "$user" "$home" "$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')" >&2

  local rel
  for rel in continuity hypr waybar eww rofi dunst; do
    rm_path "$home/.config/$rel" || true
  done
  # The GTK files may predate ContinuityOS; keep a copy of anything that is not ours.
  local g
  for g in gtk-3.0 gtk-4.0; do
    [ -f "$home/.config/$g/gtk.css" ] && rm_path "$home/.config/$g/gtk.css" || true
    [ -f "$home/.config/$g/settings.ini" ] && rm_path "$home/.config/$g/settings.ini" || true
    rmdir "$home/.config/$g" 2>/dev/null || true
  done

  rm_path "$home/.local/share/continuity" || true
  rm_path "$home/.local/state/continuity" || true
  rm_path "$home/.local/share/applications/continuity" || true
  rm_path "$home/.local/share/applications/continuity-wine.desktop" || true

  if [ "$PURGE_DATA" = "1" ]; then
    warn "removing Windows prefixes and the Steam Linux Runtime (your games and saves live in the prefixes)"
    if [ "$DRY_RUN" = "1" ] || confirm "Delete $home/.local/share/universal-prefixes and $home/.local/share/umu?"; then
      rm_path "$home/.local/share/universal-prefixes" || true
      rm_path "$home/.local/share/umu" || true
      rm_path "$home/.cache/umu" || true
    else
      warn "kept prefixes and runtimes"
    fi
  else
    say "kept $home/.local/share/universal-prefixes (use --purge-data to delete)"
    say "kept $home/.local/share/umu (use --purge-data to delete)"
  fi

  if [ -f "$home/.config/mimeapps.list" ] && [ "$DRY_RUN" != "1" ]; then
    sed -i '/continuity-wine\.desktop/d' "$home/.config/mimeapps.list"
    ok "cleaned $home/.config/mimeapps.list"
  fi

  if [ -e "$home/.config/continuity/environment.conf.continuity-backup" ]; then
    warn "your previous settings are at ~/.config/continuity/environment.conf.continuity-backup"
  fi

  if [ "$(id -u)" = "0" ]; then
    chown -R "$user" "$home/.config" 2>/dev/null || true
  fi
}

[ "$DO_SYSTEM" = "1" ] && uninstall_system
[ "$DO_USER" = "1" ] && uninstall_user

printf '\nDone. Packages were left installed on purpose — see docs/UNINSTALL.md for the optional cleanup list.\n' >&2
