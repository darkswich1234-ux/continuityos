#!/usr/bin/env bash
# ContinuityOS shell widget — audio control via WirePlumber (wpctl).
#
#   audio.sh sink-get | sink-vol | sink-mute | sink-name
#   audio.sh sink-set <0-100> | sink-mute-toggle | sink-up | sink-down
#   audio.sh source-get | source-set <0-100> | source-mute-toggle
#   audio.sh list-sinks | open
set -uo pipefail

cmd="${1:-sink-get}"
DEFAULT_SINK="@DEFAULT_AUDIO_SINK@"
DEFAULT_SOURCE="@DEFAULT_AUDIO_SOURCE@"

have_wp() { command -v wpctl >/dev/null 2>&1; }

wp() { wpctl "$@" 2>/dev/null || true; }

# clamp a percentage into 0..100
clamp() {
  local n="${1:-0}"
  case "$n" in
    ''|*[!0-9]*) n=0 ;;
  esac
  if [ "$n" -lt 0 ]; then n=0; fi
  if [ "$n" -gt 100 ]; then n=100; fi
  printf '%s' "$n"
}

sink_percent() {
  have_wp || { echo 0; return; }
  local out
  out="$(wp get-volume "$DEFAULT_SINK@")"
  printf '%s' "$out" | awk '{printf "%d", $2*100}' 2>/dev/null || echo 0
}

sink_muted() {
  have_wp || { echo 0; return; }
  if wp get-volume "$DEFAULT_SINK@" | grep -q MUTED; then echo 1; else echo 0; fi
}

case "$cmd" in
  sink-get)
    printf '%s\n' "$(sink_percent)"
    ;;
  sink-vol)
    printf '%s\n' "$(sink_percent)"
    ;;
  sink-mute)
    printf '%s\n' "$(sink_muted)"
    ;;
  sink-name)
    wp inspect "$DEFAULT_SINK@" 2>/dev/null | awk -F'"' '/node.description|node.nick|device.description/{print $2; exit}' || true
    ;;
  sink-set)
    have_wp || exit 0
    wp set-volume "$DEFAULT_SINK@" "$(clamp "${2:-0}")%" >/dev/null 2>&1 || true
    ;;
  sink-up)
    have_wp || exit 0
    wp set-volume "$DEFAULT_SINK@" 5%+ >/dev/null 2>&1 || true
    ;;
  sink-down)
    have_wp || exit 0
    wp set-volume "$DEFAULT_SINK@" 5%- >/dev/null 2>&1 || true
    ;;
  sink-mute-toggle)
    have_wp || exit 0
    wp set-mute "$DEFAULT_SINK@" toggle >/dev/null 2>&1 || true
    ;;
  source-get|source-vol)
    have_wp || { echo 0; exit 0; }
    wp get-volume "$DEFAULT_SOURCE@" | awk '{printf "%d\n", $2*100}' 2>/dev/null || echo 0
    ;;
  source-set)
    have_wp || exit 0
    wp set-volume "$DEFAULT_SOURCE@" "$(clamp "${2:-0}")%" >/dev/null 2>&1 || true
    ;;
  source-mute-toggle)
    have_wp || exit 0
    wp set-mute "$DEFAULT_SOURCE@" toggle >/dev/null 2>&1 || true
    ;;
  list-sinks)
    have_wp || exit 0
    wp status 2>/dev/null | sed -n '/Audio\/Sinks/,$p' | grep -E '^\s*[│├└]?\s*[0-9]+\.' | head -n 20
    ;;
  open)
    if command -v pavucontrol >/dev/null 2>&1; then
      setsid pavucontrol >/dev/null 2>&1 &
    elif command -v pwvucontrol >/dev/null 2>&1; then
      setsid pwvucontrol >/dev/null 2>&1 &
    fi
    ;;
  *) echo "usage: audio.sh sink-get|sink-set <n>|sink-mute-toggle|source-get|source-set <n>|source-mute-toggle|open" >&2 ;;
esac

exit 0
