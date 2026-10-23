#!/usr/bin/env bash
# ContinuityOS shell widget — system metrics for Eww/Waybar.
# Prints exactly one line; never blocks; exits 0 even with no hardware support.
#
#   system-info.sh cpu|mem|ram|mem-total|battery|battery-icon|battery-status
#                  |uptime|volume|date|time|weekday|gpu|distro
set -uo pipefail

metric="${1:-cpu}"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/continuity-widgets"
mkdir -p "$STATE_DIR" 2>/dev/null || true

read_float() { awk "BEGIN{printf \"%.0f\", $1}" 2>/dev/null || echo 0; }

cpu_usage() {
  # Delta of /proc/stat between invocations, cached in the runtime dir so a
  # 1-4s poll costs nothing and never sleeps.
  local stat_line prev user nice system idle iowait irq softirq steal
  local p_user=0 p_idle=0 p_total=0
  stat_line="$(awk '/^cpu /{ $1=""; print; exit }' /proc/stat 2>/dev/null)" || stat_line=""
  [ -n "$stat_line" ] || { echo 0; return; }
  # shellcheck disable=SC2086
  set -- $stat_line
  user="$1"; nice="$2"; system="$3"; idle="$4"; iowait="${5:-0}"; irq="${6:-0}"
  softirq="${7:-0}"; steal="${8:-0}"
  local total idle_all
  idle_all=$((idle + iowait))
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  if [ -r "$STATE_DIR/cpu.stat" ]; then
    read -r p_user p_idle p_total <"$STATE_DIR/cpu.stat" 2>/dev/null || true
  fi
  printf '%s %s %s\n' "$total" "$idle_all" "$total" >"$STATE_DIR/cpu.stat"
  if [ "${p_total:-0}" -eq 0 ] || [ "$p_total" -ge "$total" ]; then
    echo 0
    return
  fi
  local d_total d_idle
  d_total=$((total - p_total))
  d_idle=$((idle_all - p_idle))
  local used=$((d_total - d_idle))
  echo $((used * 100 / d_total))
}

mem_info() { awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{if(t>0) printf "%d %d\n", (t-a)*100/t, (t-a)/1024}' /proc/meminfo 2>/dev/null || echo "0 0"; }

battery_dir() { ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1; }

case "$metric" in
  cpu)            value="$(cpu_usage)"; printf '%s%%\n' "${value:-0}" ;;
  mem|ram)
    read -r pct _used < <(mem_info)
    printf '%s%%\n' "${pct:-0}"
    ;;
  mem-used)
    read -r _pct used < <(mem_info)
    if [ "${used:-0}" -ge 1024 ]; then printf '%s.%sGi\n' "$((used/1024))" "$(( (used%1024)*10/1024 ))"; else printf '%sMi\n' "${used:-0}"; fi
    ;;
  mem-total)
    awk '/^MemTotal:/{printf "%.0f\n", $2/1048576}' /proc/meminfo 2>/dev/null || echo 0
    ;;
  battery|battery-raw)
    dir="$(battery_dir)"
    if [ -z "$dir" ]; then echo 0; else cat "$dir/capacity" 2>/dev/null || echo 0; fi
    ;;
  battery-status)
    dir="$(battery_dir)"
    if [ -z "$dir" ]; then echo desktop; else cat "$dir/status" 2>/dev/null || echo Unknown; fi
    ;;
  battery-icon)
    dir="$(battery_dir)"
    # Nerd Font glyphs by default; CONTINUITY_GLYPH_MODE=text keeps the shell
    # readable on a machine without one (no tofu boxes).
    if [ "${CONTINUITY_GLYPH_MODE:-nerd}" = "text" ]; then
      if [ -z "$dir" ]; then echo ""; exit 0; fi
      case "$(cat "$dir/status" 2>/dev/null || echo Unknown)" in
        Charging|Full) echo "chg" ;;
        *) echo "" ;;
      esac
      exit 0
    fi
    if [ -z "$dir" ]; then echo ""; exit 0; fi
    cap="$(cat "$dir/capacity" 2>/dev/null || echo 0)"
    st="$(cat "$dir/status" 2>/dev/null || echo Unknown)"
    if [ "$st" = "Charging" ]; then echo ""; exit 0; fi
    if [ "$cap" -ge 95 ]; then echo ""
    elif [ "$cap" -ge 80 ]; then echo ""
    elif [ "$cap" -ge 60 ]; then echo ""
    elif [ "$cap" -ge 40 ]; then echo ""
    elif [ "$cap" -ge 20 ]; then echo ""
    else echo ""
    fi
    ;;
  uptime)
    awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60);
          if(d>0) printf "%dd %dh\n", d, h; else printf "%dh %dm\n", h, m}' /proc/uptime 2>/dev/null || echo ""
    ;;
  volume)
    if command -v wpctl >/dev/null 2>&1; then
      out="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
      vol="$(printf '%s' "$out" | awk '{printf "%d", $2*100}')"
      case "$out" in *MUTED*) printf 'MUTE\n' ;; *) printf '%s%%\n' "${vol:-0}" ;; esac
    else
      echo "n/a"
    fi
    ;;
  gpu)
    busy=""
    for f in /sys/class/drm/card*/device/gpu_busy_percent; do
      [ -r "$f" ] && { busy="$(cat "$f" 2>/dev/null)" && break; }
    done
    if [ -z "$busy" ] && command -v nvidia-smi >/dev/null 2>&1; then
      busy="$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)"
    fi
    printf '%s%%\n' "${busy:-0}"
    ;;
  gpu-name)
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1
    else
      for f in /sys/class/drm/card*/device/uevent; do
        [ -r "$f" ] || continue
        awk -F= '/^DRIVER=/{printf "%s\n", $2}' "$f" 2>/dev/null
        break
      done
    fi
    ;;
  date)     date '+%a %d %b' ;;
  time)     date '+%H:%M' ;;
  weekday)  date '+%A' ;;
  distro)   echo "ContinuityOS" ;;
  *)        echo "unknown metric: $metric" >&2; exit 0 ;;
esac

exit 0
