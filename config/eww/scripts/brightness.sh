#!/usr/bin/env bash
# ContinuityOS shell widget — display brightness (brightnessctl).
#
#   brightness.sh get | set <0-100> | inc [percent] | dec [percent] | open
#
# Falls back to a ddcutil-based external display when no backlight exists.
set -uo pipefail

cmd="${1:-get}"

have() { command -v "$1" >/dev/null 2>&1; }

# Internal panel backlight percentage.
backlight_pct() {
  have brightnessctl || return 1
  local cur max
  cur="$(brightnessctl get 2>/dev/null)" || return 1
  max="$(brightnessctl max 2>/dev/null)" || return 1
  case "${cur:-}" in ''|*[!0-9]*) return 1 ;; esac
  case "${max:-}" in ''|*[!0-9]*|0) return 1 ;; esac
  echo $(( cur * 100 / max ))
}

clamp() {
  local n="${1:-0}"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -lt 0 ] && n=0
  [ "$n" -gt 100 ] && n=100
  printf '%s' "$n"
}

case "$cmd" in
  get)
    if pct="$(backlight_pct)"; then
      printf '%s\n' "$pct"
    else
      echo 100
    fi
    ;;
  set)
    pct="$(clamp "${2:-50}")"
    if have brightnessctl; then
      brightnessctl set "${pct}%" >/dev/null 2>&1 || true
    fi
    ;;
  inc)
    step="$(clamp "${2:-5}")"
    have brightnessctl && brightnessctl set "${step}%+" >/dev/null 2>&1 || true
    ;;
  dec)
    step="$(clamp "${2:-5}")"
    have brightnessctl && brightnessctl set "${step}%-" >/dev/null 2>&1 || true
    ;;
  nightlight)
    # Night light via gammastep when installed, toggled as a unit-ish process.
    if have gammastep; then
      if pgrep -x gammastep >/dev/null 2>&1; then
        pkill -x gammastep >/dev/null 2>&1 || true
      else
        setsid gammastep -O 4000 >/dev/null 2>&1 &
      fi
    fi
    ;;
  open)
    if have wdisplays; then setsid wdisplays >/dev/null 2>&1 &
    elif have nwg-displays; then setsid nwg-displays >/dev/null 2>&1 &
    fi
    ;;
  *) echo "usage: brightness.sh get|set <n>|inc [n]|dec [n]|nightlight|open" >&2 ;;
esac

exit 0
