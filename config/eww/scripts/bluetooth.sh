#!/usr/bin/env bash
# ContinuityOS shell widget — Bluetooth state and toggles (bluez / bluetoothctl).
#
#   bluetooth.sh status    "On", "Off", or the connected device name
#   bluetooth.sh state     on|off|unknown
#   bluetooth.sh device    connected device name, else "Not connected"
#   bluetooth.sh toggle    power the adapter on/off
#   bluetooth.sh devices   paired devices, one per line (with * when connected)
#   bluetooth.sh scan      open a bluetooth manager (blueman/overskride)
#   bluetooth.sh icon      a single glyph for the current state
set -uo pipefail

cmd="${1:-status}"

have_bt() { command -v bluetoothctl >/dev/null 2>&1; }

bt_on() {
  have_bt || return 1
  bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'
}

connected_device() {
  have_bt || return 0
  # bluetoothctl's "Devices" list marks each entry Connected: yes|no.
  bluetoothctl devices Connected 2>/dev/null | head -n1 | sed 's/^Device [0-9A-F:]* //'
}

case "$cmd" in
  state)
    if ! have_bt; then echo unknown; exit 0; fi
    if bt_on; then echo on; else echo off; fi
    ;;
  status|device)
    if ! have_bt; then echo "No Bluetooth"; exit 0; fi
    if ! bt_on; then echo "Bluetooth off"; exit 0; fi
    dev="$(connected_device)"
    if [ -n "$dev" ]; then printf '%s\n' "$dev"; else echo "Not connected"; fi
    ;;
  devices)
    have_bt || exit 0
    bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
      [ -n "${mac:-}" ] || continue
      if bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes'; then
        printf '%s  %s\n' "$name" "$mac"
      else
        printf '%s\n' "$name"
      fi
    done
    ;;
  toggle)
    have_bt || exit 0
    if bt_on; then
      bluetoothctl power off >/dev/null 2>&1 || true
    else
      bluetoothctl power on >/dev/null 2>&1 || true
    fi
    ;;
  scan)
    if command -v overskride >/dev/null 2>&1; then
      setsid overskride >/dev/null 2>&1 &
    elif command -v blueman-manager >/dev/null 2>&1; then
      setsid blueman-manager >/dev/null 2>&1 &
    elif command -v bluetoothctl >/dev/null 2>&1; then
      setsid kitty -e bluetoothctl >/dev/null 2>&1 || true
    fi
    ;;
  icon)
    if ! have_bt; then echo ""; exit 0; fi
    if [ "${CONTINUITY_GLYPH_MODE:-nerd}" = "text" ]; then
      # Text fallback: no glyph font required.
      if bt_on; then echo "on"; else echo "off"; fi
      exit 0
    fi
    if bt_on; then
      if [ -n "$(connected_device)" ]; then echo ""; else echo ""; fi
    else
      echo ""
    fi
    ;;
  *) echo "usage: bluetooth.sh status|state|device|devices|toggle|scan|icon" >&2 ;;
esac

exit 0
