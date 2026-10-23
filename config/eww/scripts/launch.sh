#!/usr/bin/env bash
# ContinuityOS shell widget — tolerant application launcher for dock buttons.
#
#   launch.sh <spec>
#
# A spec is a | separated list of candidates; the first one found wins:
#   launch.sh "kitty|alacritty|foot|gnome-terminal"
# Unknown binaries are skipped, and a spec that starts with "desktop:" uses
# gtk-launch for a .desktop file name (e.g. desktop:steam.desktop).
set -uo pipefail

spec="${1:-}"
[ -n "$spec" ] || { echo "usage: launch.sh <cmd|cmd|desktop:name.desktop>" >&2; exit 0; }

launch_detached() {
  # setsid + full detach so the shell survives the app starting.
  setsid "$@" >/dev/null 2>&1 &
}

case "$spec" in
  desktop:*)
    entry="${spec#desktop:}"
    if command -v gtk-launch >/dev/null 2>&1; then
      launch_detached gtk-launch "${entry%.desktop}"
    fi
    exit 0
    ;;
esac

IFS='|' read -r -a candidates <<<"$spec"
for cand in "${candidates[@]}"; do
  [ -n "$cand" ] || continue
  # A candidate may be "binary arg arg"
  # shellcheck disable=SC2086
  read -r -a parts <<<"$cand"
  bin="${parts[0]}"
  if command -v "$bin" >/dev/null 2>&1; then
    launch_detached "${parts[@]}"
    exit 0
  fi
done

exit 0
