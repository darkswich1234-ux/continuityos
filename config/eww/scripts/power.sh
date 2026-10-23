#!/usr/bin/env bash
# ContinuityOS shell widget — power / session actions.
#
#   power.sh                 open a themed action menu (rofi, wofi, or TTY prompt)
#   power.sh lock|suspend|hibernate|logout|reboot|shutdown|uptime
#
# Every action is also reachable directly, so the drawer's power buttons and the
# top-bar power menu can share this one implementation.
set -uo pipefail

action="${1:-menu}"

have() { command -v "$1" >/dev/null 2>&1; }

confirm_or_run() {
  # Destructive actions always confirm unless CONTINUITY_ASSUME_YES=1
  # (rofi menus act as the confirmation when launched from the menu path).
  local prompt="$1"; shift
  if [ "${CONTINUITY_ASSUME_YES:-0}" = "1" ]; then
    "$@"
    return 0
  fi
  if have rofi; then
    result="$(printf 'No\nYes\n' | rofi -dmenu -i -p "$prompt" -theme-str 'window {width: 300px;}')" || return 0
    case "$result" in Yes|yes) "$@" ;; *) return 0 ;; esac
  else
    "$@"
  fi
}

do_lock()     { if have hyprlock; then setsid hyprlock >/dev/null 2>&1 & elif have swaylock; then setsid swaylock >/dev/null 2>&1 & elif have loginctl; then loginctl lock-session >/dev/null 2>&1 || true; fi; }
do_suspend()  { have systemctl && systemctl suspend || true; }
do_hibernate(){ have systemctl && systemctl hibernate || do_suspend; }
do_logout()   { if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && have hyprctl; then hyprctl dispatch exit >/dev/null 2>&1 || true; elif have loginctl; then loginctl terminate-session "${XDG_SESSION_ID:-}" >/dev/null 2>&1 || true; fi; }
do_reboot()   { have systemctl && systemctl reboot || true; }
do_shutdown() { have systemctl && systemctl poweroff || true; }

menu() {
  local options="Lock
Suspend
Hibernate
Log out
Reboot
Shut down"
  local choice=""
  if have rofi; then
    choice="$(printf '%s\n' "$options" | rofi -dmenu -i -p 'Power' \
      -theme-str 'window {width: 340px; border-radius: 24px;} listview {lines: 6;}')" || true
  elif have wofi; then
    choice="$(printf '%s\n' "$options" | wofi --dmenu --prompt Power)" || true
  else
    choice="$(printf '%s\n' "$options" | fzf --prompt 'Power > ' 2>/dev/null)" || true
  fi
  case "$choice" in
    Lock) do_lock ;;
    Suspend) do_suspend ;;
    Hibernate) do_hibernate ;;
    "Log out") do_logout ;;
    Reboot) confirm_or_run "Reboot?" do_reboot ;;
    "Shut down") confirm_or_run "Shut down?" do_shutdown ;;
  esac
}

case "$action" in
  menu)       menu ;;
  lock)       do_lock ;;
  suspend)    do_suspend ;;
  hibernate)  do_hibernate ;;
  logout)     do_logout ;;
  reboot)     confirm_or_run "Reboot?" do_reboot ;;
  shutdown|poweroff) confirm_or_run "Shut down?" do_shutdown ;;
  uptime)     awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); if(d>0) printf "%dd %dh\n", d, h; else printf "%dh %dm\n", h, m}' /proc/uptime ;;
  *) echo "usage: power.sh [lock|suspend|hibernate|logout|reboot|shutdown]" >&2 ;;
esac

exit 0
