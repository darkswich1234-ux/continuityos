#!/usr/bin/env bash
# ContinuityOS shell widget — notification centre data (dunst).
#
#   notifications.sh count      number of notifications in dunst history
#   notifications.sh paused     1 when do-not-disturb is on
#   notifications.sh summary    "N new notifications" style line
#   notifications.sh list       Pango markup rows, one <span> per notification
#   notifications.sh clear      close/clear all notifications
#   notifications.sh toggle-dnd pause/unpause notifications
#   notifications.sh open       open the notification centre window
#
# dunstctl prints JSON; jq is used when present (a tiny optional dependency) and
# every path degrades to a plain count or an empty list when it is not.
set -uo pipefail

cmd="${1:-summary}"

have() { command -v "$1" >/dev/null 2>&1; }
dunst_ready() { have dunstctl && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; }

json() { dunstctl "$@" 2>/dev/null || true; }

escape_markup() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

limit="${CONTINUITY_NOTIF_LIMIT:-6}"

case "$cmd" in
  count)
    if ! dunst_ready; then echo 0; exit 0; fi
    if have jq; then
      n="$(json history | jq -r '[.data[]?[]?] | length' 2>/dev/null || echo 0)"
      printf '%s\n' "${n:-0}"
    else
      printf '%s\n' "$(json count displayed 2>/dev/null || echo 0)"
    fi
    ;;
  paused)
    if ! dunst_ready; then echo 0; exit 0; fi
    p="$(json is-paused 2>/dev/null || echo false)"
    case "$p" in true|True) echo 1 ;; *) echo 0 ;; esac
    ;;
  summary)
    if ! dunst_ready; then echo "Notifications unavailable"; exit 0; fi
    if [ "$(json is-paused 2>/dev/null || echo false)" = "true" ]; then
      echo "Do not disturb"
      exit 0
    fi
    if have jq; then
      n="$(json history | jq -r '[.data[]?[]?] | length' 2>/dev/null || echo 0)"
    else
      n="$(json count displayed 2>/dev/null || echo 0)"
    fi
    case "${n:-0}" in
      0) echo "No notifications" ;;
      1) echo "1 notification" ;;
      *) printf '%s notifications\n' "$n" ;;
    esac
    ;;
  list)
    if ! dunst_ready; then exit 0; fi
    if have jq; then
      json history | jq -r --argjson lim "$limit" '
        [.data[]?[]?] | reverse | .[:$lim] | .[] |
        "<span size=\"large\" weight=\"bold\">" + ((.appname // "App") | tostring) + "</span>" +
        "\n<span weight=\"bold\">" + ((.summary // "") | tostring) + "</span>" +
        "\n<span alpha=\"70%\">" + ((.body // "") | tostring | gsub("\n"; " ")) + "</span>" +
        "\n\n"
      ' 2>/dev/null || true
    fi
    ;;
  clear)
    dunst_ready || exit 0
    dunstctl close-all >/dev/null 2>&1 || true
    dunstctl history-clear >/dev/null 2>&1 || true
    ;;
  toggle-dnd)
    dunst_ready || exit 0
    dunstctl set-paused toggle >/dev/null 2>&1 || true
    ;;
  open)
    if have continuity-panel; then
      continuity-panel toggle notifications >/dev/null 2>&1 || true
    fi
    ;;
  *) echo "usage: notifications.sh count|paused|summary|list|clear|toggle-dnd|open" >&2 ;;
esac

exit 0
