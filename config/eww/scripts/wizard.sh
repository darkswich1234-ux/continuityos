#!/usr/bin/env bash
# ContinuityOS shell widget — first-run wizard bridge.
#
# The Eww windows poll this script; it is a thin, forgiving reader over
# `continuity-wizard get`. It must never fail (a failing poll makes Eww render an
# empty label, or worse, log noise every interval), so every branch prints
# something sensible even when the wizard is not installed.
#
#   wizard.sh greeting      "Good evening, you. Let's get host set up."
#   wizard.sh page          welcome|steam|windows|mode|done
#   wizard.sh steam-info    one-line summary of the Steam situation
#   wizard.sh steam-games   number of games in the imported library
#   wizard.sh app-name      prefix name of the app being installed
#   wizard.sh app-state     human-readable install state
#   wizard.sh mode          balanced|gaming
#   wizard.sh error         last error, or nothing
#   wizard.sh prefix-root   where Windows apps live
set -uo pipefail

cmd="${1:-page}"
WIZ="${CONTINUITY_WIZARD_BIN:-}"
if [ -z "$WIZ" ]; then
  if [ -x /usr/local/bin/continuity-wizard ]; then WIZ=/usr/local/bin/continuity-wizard; else WIZ=continuity-wizard; fi
fi

have_wiz() { [ -x "$WIZ" ] || command -v "$WIZ" >/dev/null 2>&1; }

ask() {
  # ask KEY — never fails, never noisy.
  have_wiz || { printf ''; return 0; }
  "$WIZ" get "$1" 2>/dev/null || printf ''
}

case "$cmd" in
  greeting)
    out="$(ask GREETING)"
    [ -n "$out" ] || out="Welcome. Let's get this machine set up."
    printf '%s\n' "$out"
    ;;
  page)
    out="$(ask PAGE)"
    [ -n "$out" ] || out="welcome"
    printf '%s\n' "$out"
    ;;
  steam-info)
    out="$(ask STEAM_SUMMARY)"
    [ -n "$out" ] || out="Steam was not found on this machine"
    printf '%s\n' "$out"
    ;;
  steam-games)
    out="$(ask STEAM_GAMES)"
    case "$out" in ''|*[!0-9]*) out=0 ;; esac
    printf '%s\n' "$out"
    ;;
  app-name)
    ask APP_NAME
    ;;
  app-state)
    # The engine stores machine values; the UI shows sentences.
    case "$(ask APP_STATE)" in
      running)   printf 'Installing %s…\n' "$(ask APP_NAME)" ;;
      installed) printf '%s is installed — its launcher is in the app drawer\n' "$(ask APP_NAME)" ;;
      failed)    printf '%s did not install — see the install log\n' "$(ask APP_NAME)" ;;
      *)         printf 'No Windows program chosen yet\n' ;;
    esac
    ;;
  mode)
    out="$(ask MODE)"
    case "$out" in balanced|gaming) ;; *) out=balanced ;; esac
    printf '%s\n' "$out"
    ;;
  error)
    ask ERROR
    ;;
  prefix-root)
    out="$(ask PREFIX_ROOT)"
    [ -n "$out" ] || out="${CONTINUITY_PREFIX_ROOT:-$HOME/.local/share/universal-prefixes}"
    printf '%s\n' "$out"
    ;;
  region-summary)
    out="$(ask REGION_SUMMARY)"
    [ -n "$out" ] || out="Nothing read from this machine yet"
    printf '%s\n' "$out"
    ;;
  region-locale)
    out="$(ask REGION_LOCALE)"
    printf '%s\n' "${out:-not set}"
    ;;
  region-keymap)
    out="$(ask REGION_KEYMAP)"
    printf '%s\n' "${out:-not set}"
    ;;
  region-timezone)
    out="$(ask REGION_TIMEZONE)"
    printf '%s\n' "${out:-not set}"
    ;;
  region-wifi)
    out="$(ask REGION_WIFI)"
    printf '%s\n' "${out:-not connected}"
    ;;
  shakedown-state)
    # Closed vocabulary: the window colours itself from this, so an unexpected
    # value must not leak into a class name.
    out="$(ask SHAKEDOWN_STATE)"
    case "$out" in pass|warn|fail) ;; *) out=unknown ;; esac
    printf '%s\n' "$out"
    ;;
  shakedown-summary)
    out="$(ask SHAKEDOWN_SUMMARY)"
    [ -n "$out" ] || out="Not checked yet"
    printf '%s\n' "$out"
    ;;
  shakedown-headline)
    ask SHAKEDOWN_HEADLINE
    ;;
  shakedown-fix)
    out="$(ask SHAKEDOWN_FIX)"
    [ -n "$out" ] || out="nothing to fix"
    printf '%s\n' "$out"
    ;;
  transfer-state)
    out="$(ask TRANSFER_STATE)"
    case "$out" in idle|exported|imported|failed) ;; *) out=idle ;; esac
    printf '%s\n' "$out"
    ;;
  transfer-summary)
    out="$(ask TRANSFER_SUMMARY)"
    [ -n "$out" ] || out="Nothing moved yet"
    printf '%s\n' "$out"
    ;;
  *)
    printf 'usage: wizard.sh greeting|page|steam-info|steam-games|app-name|app-state|mode|error|prefix-root|region-summary|region-locale|region-keymap|region-timezone|region-wifi|shakedown-state|shakedown-summary|shakedown-headline|shakedown-fix|transfer-state|transfer-summary\n' >&2
    ;;
esac

exit 0
