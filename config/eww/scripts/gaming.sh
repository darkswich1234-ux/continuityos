#!/usr/bin/env bash
# ContinuityOS shell widget — gaming-mode bridge for the Eww drawer.
#
#   gaming.sh state    on|off            (used as a class suffix: seg-gaming-${state})
#   gaming.sh on       enable gaming mode
#   gaming.sh off      disable gaming mode
#   gaming.sh toggle
#   gaming.sh label    human readable status line
set -uo pipefail

cmd="${1:-state}"
mode_bin="/usr/local/bin/continuity-gaming-mode"
have_mode() { [ -x "$mode_bin" ] || command -v continuity-gaming-mode >/dev/null 2>&1; }

run_mode() {
  if [ -x "$mode_bin" ]; then
    "$mode_bin" "$@" >/dev/null 2>&1 || true
  elif command -v continuity-gaming-mode >/dev/null 2>&1; then
    continuity-gaming-mode "$@" >/dev/null 2>&1 || true
  fi
}

case "$cmd" in
  state)
    state_file="${XDG_STATE_HOME:-$HOME/.local/state}/continuity/gaming-mode.enabled"
    if [ -f "$state_file" ]; then echo "on"; else echo "off"; fi
    ;;
  on|off|toggle)
    run_mode "$cmd"
    ;;
  label)
    state_file="${XDG_STATE_HOME:-$HOME/.local/state}/continuity/gaming-mode.enabled"
    if [ -f "$state_file" ]; then echo "Gaming"; else echo "Balanced"; fi
    ;;
  *) echo "usage: gaming.sh state|on|off|toggle|label" >&2 ;;
esac

exit 0
