#!/usr/bin/env bash
# ContinuityOS shell widget — Wi-Fi state and toggles (NetworkManager).
#
#   wifi.sh status     connected SSID, else "Off" / "Disconnected"
#   wifi.sh state      on|off
#   wifi.sh signal     signal strength percentage, else 0
#   wifi.sh toggle     enable/disable the radio
#   wifi.sh list       nearby SSIDs, one per line
#   wifi.sh open       open the network settings panel (nm-connection-editor)
#   wifi.sh icon       a single glyph for the current state
set -uo pipefail

cmd="${1:-status}"

have_nm() { command -v nmcli >/dev/null 2>&1; }

run() { nmcli "$@" 2>/dev/null || true; }

case "$cmd" in
  state)
    if ! have_nm; then echo "unknown"; exit 0; fi
    radio="$(run radio wifi | head -n1)"
    printf '%s\n' "$radio"
    ;;
  status)
    if ! have_nm; then echo "No NetworkManager"; exit 0; fi
    status="$(run -t -f WIFI,STATE general status)"
    if printf '%s' "$status" | grep -q '^WIFI:disabled'; then
      echo "Wi-Fi off"
      exit 0
    fi
    ssid="$(run -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')"
    if [ -n "$ssid" ]; then
      printf '%s\n' "$ssid"
    else
      echo "Disconnected"
    fi
    ;;
  signal)
    if ! have_nm; then echo 0; exit 0; fi
    sig="$(run -t -f IN-USE,SIGNAL dev wifi | awk -F: '$1=="*"{print $2; exit}')"
    printf '%s\n' "${sig:-0}"
    ;;
  list)
    if ! have_nm; then exit 0; fi
    run -t -f SSID,SIGNAL dev wifi list | awk -F: 'length($1)>0 && $1!=""{printf "%s  %s%%\n", $1, $2}' | sort -u | head -n 12
    ;;
  toggle)
    if ! have_nm; then exit 0; fi
    if [ "$(nmcli radio wifi 2>/dev/null | head -n1)" = "enabled" ]; then
      nmcli radio wifi off >/dev/null 2>&1 || true
    else
      nmcli radio wifi on >/dev/null 2>&1 || true
    fi
    ;;
  open)
    if command -v nm-connection-editor >/dev/null 2>&1; then
      setsid nm-connection-editor >/dev/null 2>&1 &
    elif command -v nmtui >/dev/null 2>&1; then
      setsid kitty -e nmtui >/dev/null 2>&1 || setsid xterm -e nmtui >/dev/null 2>&1 &
    fi
    ;;
  icon)
    if ! have_nm; then echo ""; exit 0; fi
    if [ "${CONTINUITY_GLYPH_MODE:-nerd}" = "text" ]; then
      # Text fallback: no glyph font required.
      if printf '%s' "$(nmcli radio wifi 2>/dev/null || true)" | grep -q disabled; then
        echo "off"
      elif [ -n "$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1; exit}')" ]; then
        echo "on"
      else
        echo "n/a"
      fi
      exit 0
    fi
    if printf '%s' "$(nmcli radio wifi 2>/dev/null || true)" | grep -q disabled; then
      echo ""
      exit 0
    fi
    ssid="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1; exit}')"
    if [ -z "$ssid" ]; then echo ""
    else
      sig="$(nmcli -t -f IN-USE,SIGNAL dev wifi 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')"
      case "${sig:-0}" in
        ''|0) echo "" ;;
        [1-9]|[1-2][0-9]) echo "" ;;
        [3-5][0-9]) echo "" ;;
        *) echo "" ;;
      esac
    fi
    ;;
  *) echo "usage: wifi.sh status|state|signal|toggle|list|open|icon" >&2 ;;
esac

exit 0
