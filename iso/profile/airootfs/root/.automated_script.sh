#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ContinuityOS live medium — boot hook.
#
# This medium is not an installer console any more. It boots into the
# ContinuityOS desktop, the way the installed system does, and the guided
# installer (/opt/continuityos/bin/continuity-installer) is what fills the
# screen. This hook is the part that must happen *before* a session can exist:
#
#   1. make sure the live account exists,
#   2. bring up networking (archinstall needs a network),
#   3. install the continuity-* CLI, the session and the live user's ~/.config
#      into this live root from the embedded payload at /opt/continuityos,
#   4. configure greetd for a no-greeter autologin, from the repository's own
#      template, with a minimal fallback if that tool is missing or refuses,
#   5. if the boot command line asked for it, start an install: unattended when
#      it named a disk, and otherwise nothing — the guided installer is already
#      on screen, and it is the one that must ask which disk to erase.
#
# Deliberately NOT `set -e`: a live hook that aborts on the first non-fatal
# error leaves the user with a black screen and no explanation. Every step
# reports what it did, and the last word is always what the user should do next.
#
# It runs exactly once, from continuity-live-boot.service. (The old root-autologin
# path is gone with root's console: the desktop owns tty1 now.)
# ---------------------------------------------------------------------------

set -uo pipefail

REPO_DIR="/opt/continuityos"
LIVE_USER="continuity"
LIVE_HOME="/home/continuity"
LOG="/var/log/continuity-live.log"
INSTALL_LOG="/var/log/continuity-installer.log"
# What the session should put in front of the user: 'guided' (the installer) or
# 'unattended' (an install is already running in the background).
MODE_FILE="/run/continuity-installer.mode"

# One line to the log and to the journal, in that order, so `less` on the log
# gives the same story as `journalctl -u continuity-live-boot`.
log() { printf '%s\n' "$*" | tee -a "$LOG" >&2; }

banner() {
  log ""
  log "   ______            __             _ __      ____  _____"
  log "  / ____/___  ____  / /__________  (_) /_ __ / __ \\/ ___/"
  log " / /   / __ \\/ __ \\/ __/ ___/ __ \\/ / __/ // / / / /\\__ \\"
  log "/ /___/ /_/ / / / / /_/ /  / /_/ / / /_/ // /_/ / /___  \\ \\"
  log "\\____/\\____/_/ /_/\\__/_/   \\____/_/\\__/\\__, /____/\\____/ /_/"
  log "                                      /____/"
  log ""
  log "  Universal Windows Compatibility Engine · live medium"
  log "  $(cat /etc/continuity-version 2>/dev/null || echo 'live')"
  log ""
}

cmdline_value() {
  awk -v k="$1" '
    { for (i = 1; i <= NF; i++) if (index($i, k "=") == 1) { sub(/^[^=]*=/, "", $i); print $i; exit } }
  ' /proc/cmdline 2>/dev/null
}

# The payload comes off a medium that may not preserve exec bits (a Windows
# checkout, a plain rsync), and every later step depends on these running.
ensure_payload_perms() {
  [ -x "$REPO_DIR/install.sh" ] && chmod 0755 "$REPO_DIR/install.sh" 2>/dev/null
  if [ -d "$REPO_DIR/bin" ]; then
    find "$REPO_DIR/bin" -maxdepth 1 -type f -exec chmod 0755 {} + 2>/dev/null
  fi
  [ -f "$REPO_DIR/iso/build.sh" ] && chmod 0755 "$REPO_DIR/iso/build.sh" 2>/dev/null
  return 0
}

ensure_live_user() {
  if getent passwd "$LIVE_USER" >/dev/null 2>&1; then
    log "live account: $LIVE_USER"
  else
    log "live account $LIVE_USER is missing (sysusers did not create it) — creating it now"
    useradd -m -s /bin/bash -G network,video,render,audio "$LIVE_USER" >/dev/null 2>&1 \
      || log "  could not create $LIVE_USER — the desktop will not start"
  fi
  if [ ! -d "$LIVE_HOME" ]; then
    mkdir -p "$LIVE_HOME" 2>/dev/null
  fi
  chown "$LIVE_USER:$(id -gn "$LIVE_USER" 2>/dev/null || echo "$LIVE_USER")" "$LIVE_HOME" 2>/dev/null
  return 0
}

network_up() {
  command -v systemctl >/dev/null 2>&1 || return 0
  if systemctl start NetworkManager >/dev/null 2>&1; then
    log "NetworkManager: up"
  else
    log "NetworkManager did not start — an install will need a network, so check 'systemctl status NetworkManager'"
  fi
  return 0
}

# [multilib] is enabled here, by hand, rather than leaving it to install.sh's
# enable_multilib: that path also runs `pacman -Sy`, which needs a working
# network this early in boot, and a failed sync would abort the whole
# provisioning step and cost us the desktop. Same edit, without the network.
enable_multilib_offline() {
  [ -r /etc/pacman.conf ] || return 0
  if grep -qE '^[[:space:]]*\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    log "[multilib]: already enabled"
    return 0
  fi
  cp -a /etc/pacman.conf /etc/pacman.conf.continuity-backup 2>/dev/null
  sed -i -E '0,/^[[:space:]]*#[[:space:]]*\[multilib\]/s//[multilib]/' /etc/pacman.conf 2>/dev/null
  sed -i -E '/^\[multilib\]/,/^\[/{s|^[[:space:]]*#[[:space:]]*(Include[[:space:]]*=[[:space:]]*/etc/pacman.d/mirrorlist)|\1|}' \
    /etc/pacman.conf 2>/dev/null
  if grep -qE '^[[:space:]]*\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    log "[multilib]: enabled (the 32-bit stack umu, wine and the lib32-* drivers need)"
  else
    log "[multilib] could not be enabled — install.sh --system will try again with a network"
  fi
  return 0
}

# The live root becomes a working ContinuityOS by running the payload's own
# installer with --skip-packages: the packages are already in the squashfs, but
# the CLI, the session entry, the config tree and /etc files are not.
provision_live_root() {
  if [ ! -x "$REPO_DIR/install.sh" ]; then
    log "The installer payload is missing ($REPO_DIR/install.sh)."
    log "Rebuild the medium with iso/build.sh — that script embeds this repository"
    log "into the squashfs, and without it this live system cannot set itself up."
    return 1
  fi
  log "Provisioning this live root from $REPO_DIR (no packages — the medium already has them)"
  if "$REPO_DIR/install.sh" --system --yes --skip-packages --src "$REPO_DIR" >>"$LOG" 2>&1; then
    log "  system files: the continuity-* CLI and the ContinuityOS session"
  else
    log "  install.sh --system failed (see the log above) — the desktop may not start"
  fi
  if "$REPO_DIR/install.sh" --user "$LIVE_USER" --yes --skip-packages --src "$REPO_DIR" >>"$LOG" 2>&1; then
    log "  $LIVE_USER's configuration, wallpapers and mime handlers"
  else
    log "  install.sh --user failed (see the log above)"
  fi
  if [ ! -x /usr/local/bin/continuity-shell ]; then
    log "  !! /usr/local/bin/continuity-shell is missing: the session will not start"
  fi
  return 0
}

# greetd's [initial_session] is the whole no-greeter design. It is written by the
# repository's own tool so there is one source of truth for the file format; the
# fallback below exists only so that a broken tool cannot turn the live medium
# into a black screen.
configure_autologin() {
  mkdir -p /etc/greetd 2>/dev/null
  if [ -x "$REPO_DIR/bin/continuity-boot" ]; then
    if "$REPO_DIR/bin/continuity-boot" on --user "$LIVE_USER" >>"$LOG" 2>&1; then
      log "autologin configured by continuity-boot (no greeter at boot, session runs directly)"
      return 0
    fi
    log "continuity-boot on failed — falling back to a minimal /etc/greetd/config.toml"
  else
    log "bin/continuity-boot is missing from this build — writing a minimal /etc/greetd/config.toml"
  fi
  cat >/etc/greetd/config.toml <<EOF
# Written by /root/.automated_script.sh as a fallback: continuity-boot was
# missing or refused. Same shape as the repository's template
# (config/greetd/config.toml.tmpl) — [initial_session] means no greeter at boot.
[terminal]
vt = 1

[default_session]
command = "agreety --cmd /bin/sh"
user = "greeter"

[initial_session]
command = "/usr/local/bin/continuity-shell"
user = "$LIVE_USER"
EOF
  chmod 0644 /etc/greetd/config.toml 2>/dev/null
  log "  wrote /etc/greetd/config.toml (autologin as $LIVE_USER)"
  return 0
}

# Only ever reached when someone typed continuityos.install=1 — and even then it
# refuses to guess a disk, because "which disk" is the one question that must
# never be replied to on the user's behalf.
maybe_unattended_install() {
  local cmdline disk user host tz locale
  cmdline="$(cat /proc/cmdline 2>/dev/null || true)"
  case "$cmdline" in
    *continuityos.install=1*) ;;
    *) return 0 ;;
  esac

  disk="$(cmdline_value continuityos.disk)"
  user="$(cmdline_value continuityos.user)"
  host="$(cmdline_value continuityos.host)"
  tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  locale="$(awk -F= '/^[[:space:]]*LANG=/ {print $2; exit}' /etc/locale.conf 2>/dev/null || true)"

  if [ -z "$disk" ]; then
    log "continuityos.install=1 without continuityos.disk= — not guessing: the guided"
    log "installer is on the desktop, and it will ask which disk to erase."
    return 0
  fi
  if [ ! -x "$REPO_DIR/bin/continuity-installer" ]; then
    log "continuityos.install=1 was requested but bin/continuity-installer is missing"
    return 1
  fi

  log "Unattended install requested on the kernel command line: $disk"
  # setsid + & because this unit is Type=oneshot RemainAfterExit, so its cgroup
  # survives and the install outlives the hook.
  setsid "$REPO_DIR/bin/continuity-installer" install \
    --disk "$disk" \
    --user "${user:-$LIVE_USER}" \
    --host "${host:-continuity}" \
    --timezone "${tz:-UTC}" \
    --locale "${locale:-en_US.UTF-8}" \
    --log "$INSTALL_LOG" \
    --yes >>"$INSTALL_LOG" 2>&1 &
  printf 'unattended\n' >"$MODE_FILE" 2>/dev/null
  log "  running in the background (pid $!) — progress: tail -f $INSTALL_LOG"
  log "  it will refuse --yes without continuityos.disk=, which is why that is required above"
  return 0
}

# ---------------------------------------------------------------------------
banner
ensure_payload_perms
ensure_live_user
network_up
enable_multilib_offline

if provision_live_root; then
  configure_autologin
else
  log "Without the payload this medium can only offer a shell; the installer UI is not available."
fi

maybe_unattended_install

# The live session reads this to decide what to put in front of the user. It is
# written last so that an unattended install can overwrite it.
if [ ! -e "$MODE_FILE" ]; then
  printf 'guided\n' >"$MODE_FILE" 2>/dev/null
fi

log ""
log "ContinuityOS live session: the desktop comes up as '$LIVE_USER' with no login prompt."
log "  Guided installer : on the desktop (or: $REPO_DIR/bin/continuity-installer ui)"
log "  Install log      : $INSTALL_LOG"
log "  This boot log    : $LOG"
log "  Reminder         : this medium keeps changes in RAM and forgets them on reboot."
log ""
