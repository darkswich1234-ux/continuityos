#!/usr/bin/env bash
# ContinuityOS engine — offline checks.
#
#   tests/run.sh              everything
#   tests/run.sh --syntax     bash -n plus the repository contract only
#
# The suite needs no root, no network, no Windows program and no Arch: the whole
# point of the standalone engine is that it degrades gracefully, and these checks
# prove it. Run it after every change.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

if [ -t 1 ]; then C_RESET=$'\033[0m'; C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
else C_RESET=''; C_GRN=''; C_RED=''; C_DIM=''; C_BLD=''; fi

PASS=0
FAIL=0
FAILED_NAMES=()
pass() { PASS=$((PASS+1)); printf '  %sPASS%s %s\n' "$C_GRN" "$C_RESET" "$1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  %sFAIL%s %s\n' "$C_RED" "$C_RESET" "$1"; }
group() { printf '\n%s%s%s\n' "$C_BLD" "$1" "$C_RESET"; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT

MODE="all"
case "${1:-}" in
  --syntax) MODE="syntax" ;;
  ""|--all) MODE="all" ;;
  *) echo "usage: tests/run.sh [--syntax]" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# syntax and repository contract
# ---------------------------------------------------------------------------
syntax_checks() {
  group "Shell syntax (bash -n)"
  local f out
  local files=(install.sh tests/run.sh)
  while IFS= read -r f; do files+=("$f"); done < <(find bin lib -type f | sort)

  for f in "${files[@]}"; do
    [ -f "$f" ] || { fail "missing file: $f"; continue; }
    head -1 "$f" | grep -qE '^#!.*(bash|sh)' || continue
    if out="$(bash -n "$f" 2>&1)"; then
      pass "bash -n $f"
    else
      fail "bash -n $f"
      printf '%s\n' "$out" | sed 's/^/        /'
    fi
  done

  group "ShellCheck (optional)"
  if command -v shellcheck >/dev/null 2>&1; then
    local sc=0
    for f in "${files[@]}"; do
      shellcheck -S warning "$f" >/dev/null 2>&1 || { sc=$((sc+1)); fail "shellcheck $f"; }
    done
    [ "$sc" -eq 0 ] && pass "shellcheck is clean"
  else
    printf '  %sSKIP%s shellcheck is not installed\n' "$C_DIM" "$C_RESET"
  fi

  group "Repository contract"
  local needed=(
    install.sh bin/proton bin/continuity-run bin/continuity-prefix
    bin/continuity-shakedown lib/continuity-common.sh
    config/environment.conf docs/ENGINE.md README.md tests/run.sh
  )
  for f in "${needed[@]}"; do
    [ -e "$f" ] && pass "present: $f" || fail "missing: $f"
  done
  for f in install.sh bin/proton bin/continuity-run bin/continuity-prefix bin/continuity-shakedown; do
    [ -x "$f" ] && pass "executable: $f" || fail "not executable: $f"
  done
  # The repository is the proton engine only: none of the old OS project may be here.
  local leftover
  for leftover in iso config/hypr config/eww config/waybar systemd packages desktop sessions pacman etc tools assets; do
    [ -e "$leftover" ] && fail "OS project leftover: $leftover" || pass "gone: $leftover"
  done
  if grep -qE 'continuity-(boot|wizard|panel|gaming-mode|installer|export|region)\b' install.sh bin/* lib/*.sh 2>/dev/null; then
    fail "the engine still references a removed tool"
  else
    pass "no references to removed tools"
  fi
  if grep -q 'standalone/' install.sh bin/* lib/*.sh 2>/dev/null; then
    fail "the engine still points at the old standalone/ path"
  else
    pass "paths are the flat layout"
  fi
  grep -q 'eol=lf' .gitattributes && pass ".gitattributes keeps checkouts LF" || fail "no LF rule in .gitattributes"
  grep -q '^\*\.iso$' .gitignore && pass ".gitignore excludes ISO media" || fail ".gitignore no longer excludes ISO media"
}

# ---------------------------------------------------------------------------
# the installer
# ---------------------------------------------------------------------------
installer_checks() {
  local t="$TMP/installer" out rc
  local home="$t/home"
  mkdir -p "$t" "$home"

  group "install.sh · contract"
  bash install.sh --help 2>&1 | grep -q -- '--system' && pass "--system is documented" || fail "--system is not documented"
  bash install.sh --help 2>&1 | grep -q -- '--user' && pass "--user is documented" || fail "--user is not documented"
  bash install.sh --help 2>&1 | grep -q -- '--uninstall' && pass "--uninstall is documented" || fail "--uninstall is not documented"
  bash install.sh --help 2>&1 | grep -q 'sudo ./install.sh' && pass "the root-level install is the documented default" || fail "help does not document sudo ./install.sh"
  bash install.sh --nonsense >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && pass "an unknown flag exits 2" || fail "an unknown flag exited $rc (want 2)"

  group "install.sh · the dry run"
  out="$(HOME="$home" bash install.sh --dry-run 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && pass "the dry run succeeds" || fail "the dry run failed (rc=$rc): $out"
  case "$out" in
    *"install -m 0755"*proton*) pass "it prints the file installation" ;;
    *) fail "the dry run did not describe the install" ;;
  esac
  if [ "$(id -u)" = "0" ]; then
    case "$out" in
      *"install target: /usr/local/bin"*) pass "root installs for every user by default" ;;
      *) fail "a root dry run did not target /usr/local/bin" ;;
    esac
  else
    case "$out" in
      *"install target: $home/.local/bin"*) pass "a normal user installs into their own home" ;;
      *) fail "a user dry run did not target ~/.local/bin" ;;
    esac
  fi
  [ -z "$(find "$home" -mindepth 1 -print -quit)" ] && pass "the dry run wrote nothing into HOME" || fail "the dry run created files"

  group "install.sh · a user install (offline)"
  out="$(HOME="$home" bash install.sh --user --yes --no-download --no-desktop --no-path 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && pass "the install completes" || fail "the install failed (rc=$rc): $out"
  local f
  for f in proton continuity-run continuity-prefix continuity-shakedown; do
    [ -x "$home/.local/bin/$f" ] && pass "$f is installed" || fail "$f was not installed"
  done
  [ -r "$home/.local/lib/continuity/continuity-common.sh" ] && pass "the shared library is installed" || fail "the shared library is missing"
  [ -r "$home/.config/continuity/environment.conf" ] && pass "the default configuration is written" || fail "no configuration was written"
  printf '\n# local edit\n' >>"$home/.config/continuity/environment.conf"
  HOME="$home" bash install.sh --user --yes --no-download --no-desktop --no-path >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "a second install is idempotent" || fail "re-installing failed (rc=$rc)"
  grep -q '# local edit' "$home/.config/continuity/environment.conf" && \
    pass "an existing configuration is never overwritten" || fail "the install replaced the user's configuration"

  group "install.sh · Windows checkouts (CRLF)"
  # A CRLF shebang makes the kernel look for an interpreter called "bash\r", so
  # every installed command would be unrunnable while the source looks fine.
  local cs="$t/crlf-src" ch="$t/crlf-home"
  mkdir -p "$cs/bin" "$cs/lib" "$cs/config" "$ch"
  cp install.sh "$cs/install.sh"
  cp lib/continuity-common.sh "$cs/lib/"
  cp config/environment.conf "$cs/config/"
  cp bin/proton bin/continuity-prefix bin/continuity-shakedown "$cs/bin/"
  sed 's/$/\r/' bin/continuity-run >"$cs/bin/continuity-run"
  chmod +x "$cs/bin/continuity-run"
  HOME="$ch" bash "$cs/install.sh" --user --yes --no-download --no-desktop --no-path >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "an install from a CRLF source tree completes" || fail "the CRLF install failed (rc=$rc)"
  if head -1 "$ch/.local/bin/continuity-run" | grep -q $'\r'; then
    fail "the installed command kept a CRLF shebang"
  else
    pass "installed commands are normalised to Unix line endings"
  fi
  if HOME="$ch" "$ch/.local/bin/continuity-run" --version >/dev/null 2>&1; then
    pass "the normalised command actually runs"
  else
    fail "the normalised command did not run"
  fi

  group "install.sh · never clobbers foreign files"
  local fh="$t/foreign"
  mkdir -p "$fh/.local/bin"
  printf '#!/bin/sh\necho not-ours\n' >"$fh/.local/bin/proton"
  HOME="$fh" bash install.sh --user --yes --no-download --no-desktop --no-path >/dev/null 2>&1 && \
    fail "a foreign proton was overwritten" || pass "a foreign proton in the target directory is refused"
  grep -q 'not-ours' "$fh/.local/bin/proton" && pass "the foreign file is untouched" || fail "the foreign file changed"
}

# ---------------------------------------------------------------------------
# the command
# ---------------------------------------------------------------------------
command_checks() {
  local t="$TMP/command" out rc fam
  local home="$t/home"
  mkdir -p "$t" "$home"
  HOME="$home" bash install.sh --user --yes --no-download --no-desktop --no-path >/dev/null 2>&1
  local envp=(env HOME="$home" PATH="$home/.local/bin:$PATH")

  group "proton · running and reporting"
  out="$("${envp[@]}" proton version 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && pass "proton version runs from the install" || fail "proton version failed (rc=$rc): $out"
  case "$out" in
    *"ContinuityOS engine"*) pass "it identifies the engine" ;;
    *) fail "unexpected version output: $out" ;;
  esac
  "${envp[@]}" proton --help 2>&1 | grep -q 'USAGE' && pass "proton --help prints usage" || fail "proton --help failed"
  "${envp[@]}" proton >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "no arguments prints usage and exits 0" || fail "no arguments exited $rc"
  "${envp[@]}" proton list >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "proton list succeeds with no prefixes" || fail "proton list exited $rc"

  group "proton · prefixes"
  mkdir -p "$home/.local/share/universal-prefixes/demo/drive_c/Program Files/Demo"
  : >"$home/.local/share/universal-prefixes/demo/drive_c/Program Files/Demo/game.exe"
  [ "$("${envp[@]}" proton list)" = "demo" ] && pass "proton list shows the prefix" || fail "proton list did not show the prefix"
  # Capture, never pipe into grep -q: a short-circuiting grep closes the pipe and
  # under `set -o pipefail` the assertion fails on SIGPIPE, not on the output.
  out="$("${envp[@]}" proton scan demo 2>/dev/null)"
  case "$out" in *game.exe*) pass "proton scan finds the executable" ;; *) fail "proton scan found nothing" ;; esac
  out="$("${envp[@]}" proton info demo 2>/dev/null)"
  case "$out" in *drive_c:*) pass "proton info reports the prefix" ;; *) fail "proton info failed: $out" ;; esac
  : >"$t/x.exe"
  out="$("${envp[@]}" proton --print-env "$t/x.exe" 2>&1)"
  case "$out" in
    *CONTINUITY_PREFIX_DIR=*) pass "proton --print-env resolves a prefix (and launches nothing)" ;;
    *) fail "--print-env did not resolve a launch environment: $out" ;;
  esac
  "${envp[@]}" proton rm demo --yes >/dev/null 2>&1
  [ ! -e "$home/.local/share/universal-prefixes/demo" ] && pass "proton rm deletes the prefix" || fail "proton rm left the prefix behind"

  group "proton · distribution-aware advice"
  out="$("${envp[@]}" proton check --fix 2>&1)"
  fam="$(CONTINUITY_LIB="$home/.local/lib/continuity/continuity-common.sh" bash -c '. "$CONTINUITY_LIB"; continuity_family')"
  case "$fam" in
    debian)
      case "$out" in *pacman*) fail "a Debian host is told to run pacman" ;; *) pass "the remedies use the host's package manager" ;; esac ;;
    arch)
      case "$out" in *"apt install"*) fail "an Arch host is told to run apt" ;; *) pass "the remedies use the host's package manager" ;; esac ;;
    *)
      pass "the remedies are built for $fam" ;;
  esac
  case "$out" in
    *"SUMMARY"*) pass "proton check prints a full report" ;;
    *) fail "proton check printed no report" ;;
  esac

  group "proton · uninstall"
  mkdir -p "$home/.local/share/universal-prefixes/keepme/drive_c"
  "${envp[@]}" proton uninstall --yes >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "proton uninstall succeeds" || fail "uninstall exited $rc"
  [ ! -e "$home/.local/bin/proton" ] && pass "the command is gone" || fail "proton survived uninstall"
  [ -d "$home/.local/share/universal-prefixes/keepme" ] && pass "uninstall keeps the prefixes" || fail "uninstall deleted a prefix"
  [ -r "$home/.config/continuity/environment.conf" ] && pass "uninstall keeps the configuration" || fail "uninstall deleted the configuration"

  group "proton · uninstall --purge"
  HOME="$home" bash install.sh --user --yes --no-download --no-desktop --no-path >/dev/null 2>&1
  "${envp[@]}" proton uninstall --yes --purge >/dev/null 2>&1
  [ ! -e "$home/.local/share/universal-prefixes" ] && pass "--purge removes the prefixes" || fail "--purge left the prefixes"
  [ ! -e "$home/.config/continuity" ] && pass "--purge removes the configuration" || fail "--purge left the configuration"
}

syntax_checks
if [ "$MODE" = "all" ]; then
  installer_checks
  command_checks
fi

printf '\n%s%d passed, %d failed%s\n' "$C_BLD" "$PASS" "$FAIL" "$C_RESET"
if [ "$FAIL" -gt 0 ]; then
  printf '%sfailures:%s\n' "$C_RED" "$C_RESET"
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
printf 'All checks passed.\n'
exit 0
