#!/usr/bin/env bash
# ContinuityOS engine — the `proton` command, installed at root level.
#
# One command that runs Windows programs through Proton on the Linux the machine
# already runs: no ISO, no desktop environment, no distribution of its own.
#
#   sudo ./install.sh              install for every user (/usr/local)
#   ./install.sh                   install for the current account (~/.local)
#   ./install.sh --dry-run         print every action, change nothing
#   ./install.sh --uninstall       remove it again (sudo for a system install)
#
# What it installs
#   bin/      proton, continuity-run, continuity-prefix, continuity-shakedown
#   lib/      continuity-common.sh
#   umu-run   the Proton runtime launcher, downloaded from the upstream
#             umu-launcher release when the distribution has no package for it
#   .desktop  the .exe handler and the MIME defaults that make a double-clicked
#             .exe open in Proton
#   config    environment.conf (the defaults for the account, or /etc/skel for
#             new accounts on a system-wide install)
#
# What it does not touch: boot, display manager, session, desktop shell, systemd
# units, package-manager configuration, or any other user's files.
set -euo pipefail

SELF="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"
SRC_DIR="$(cd -- "$(dirname -- "$SELF")" && pwd)"

# Root installs for everyone by default: `sudo ./install.sh` is the documented
# command, and sending root's install into /root/.local would help nobody.
MODE="$([ "$(id -u)" = "0" ] && printf 'system' || printf 'user')"
DRY_RUN=0
ASSUME_YES=0
FORCE=0
WITH_WINE=0
WITH_DEPS=0
DESKTOP=1
WRITE_PATH=1
NO_DOWNLOAD=0
ENGINE_PATH=""
UNINSTALL=0
PURGE=0

UMU_PLANNED=0

ENGINE_FILES=(proton continuity-run continuity-prefix continuity-shakedown)
MIME_TYPES=(
  application/x-ms-dos-executable
  application/x-msdownload
  application/x-ms-shortcut
  application/vnd.microsoft.portable-executable
  application/x-msi
)

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_DIM=''; C_GRN=''; C_YLW=''; C_BLD=''
fi

step() { printf '\n%s==> %s%s\n' "$C_BLD" "$*" "$C_RESET" >&2; }
say()  { printf '  %s\n' "$*" >&2; }
ok()   { printf '  %sok%s %s\n' "$C_GRN" "$C_RESET" "$*" >&2; }
warn() { printf '  %swarning%s %s\n' "$C_YLW" "$C_RESET" "$*" >&2; }
die()  { printf '%s error: %s%s\n' "$C_YLW" "$*" "$C_RESET" >&2; exit 1; }

# Every mutation goes through run() so --dry-run cannot lie.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '  %s+ %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2
    return 0
  fi
  "$@"
}

usage() {
  cat <<'EOF'
ContinuityOS — engine-only installer for an existing Linux install

USAGE
  sudo ./install.sh [options]      (as root: every user, /usr/local)
  ./install.sh [options]           (as a user: this account, ~/.local)

TARGET
  --system             install into /usr/local for every user (needs root)
  --user               install into this account's ~/.local even when run as root
  --bin DIR            install the commands here   (default: ~/.local/bin)
  --lib DIR            install the shared library here
                       (default: ~/.local/lib/continuity)

ENGINE
  --engine PATH        use this umu-run instead of downloading one
  --no-download        never download umu-run; install the commands only
  --with-wine          also install Wine (needed for .msi, .lnk and --native)
  --with-deps          install missing prerequisites with the system package
                       manager (python3, curl/wget) instead of stopping

DESKTOP
  --no-desktop         do not register the .exe handler
  --no-path            do not add ~/.local/bin to your shell profile

OTHER
  --dry-run            print every action and change nothing
  --yes                do not ask for confirmation
  --force              overwrite files in the target directory that this
                       project did not create
  --uninstall [--purge] remove the engine; --purge also deletes the config and
                       every Windows prefix
  -h, --help           this help

WHAT YOU GET
  proton <file.exe>          run a Windows program in its own Proton prefix
  proton --installer <exe>   install, then register launchers
  proton list | info | rm    manage prefixes
  proton check               Vulkan / Wine / Proton / UMU readiness report
  proton uninstall           remove the command again

The Proton runtime itself (~1 GB) is downloaded by umu-run on the first launch,
not by this script. See docs/ENGINE.md.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --system)      MODE="system"; shift ;;
    --user)        MODE="user"; shift ;;
    --bin)         [ $# -ge 2 ] || die "--bin needs a directory"; BIN_OVERRIDE="$2"; shift 2 ;;
    --lib)         [ $# -ge 2 ] || die "--lib needs a directory"; LIB_OVERRIDE="$2"; shift 2 ;;
    --engine)      [ $# -ge 2 ] || die "--engine needs a path"; ENGINE_PATH="$2"; shift 2 ;;
    --no-download) NO_DOWNLOAD=1; shift ;;
    --with-wine)   WITH_WINE=1; shift ;;
    --with-deps)   WITH_DEPS=1; shift ;;
    --no-desktop)  DESKTOP=0; shift ;;
    --no-path)     WRITE_PATH=0; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --yes|-y)      ASSUME_YES=1; shift ;;
    --force)       FORCE=1; shift ;;
    --uninstall)   UNINSTALL=1; shift ;;
    --purge)       PURGE=1; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) printf 'unknown argument: %s (see --help)\n' "$1" >&2; exit 2 ;;
  esac
done

BIN_OVERRIDE="${BIN_OVERRIDE:-}"
LIB_OVERRIDE="${LIB_OVERRIDE:-}"
WORK_TMP=""
# The trap runs under `set -e`: a failing `[ -n "" ]` in here would become the
# installer's exit status, so the cleanup always succeeds.
cleanup() {
  if [ -n "$WORK_TMP" ]; then rm -rf -- "$WORK_TMP"; fi
  return 0
}
trap cleanup EXIT

# --- the engine's own library, for family detection and package hints --------
if [ ! -r "$SRC_DIR/lib/continuity-common.sh" ]; then
  die "lib/continuity-common.sh is missing — run this from a complete checkout"
fi
# shellcheck source=../lib/continuity-common.sh
. "$SRC_DIR/lib/continuity-common.sh"
continuity_load_env

# ---------------------------------------------------------------------------
#  paths
# ---------------------------------------------------------------------------
resolve_paths() {
  if [ "$MODE" = "system" ]; then
    BIN_DIR="${BIN_OVERRIDE:-/usr/local/bin}"
    LIB_DIR="${LIB_OVERRIDE:-/usr/local/lib/continuity}"
    APP_DIR="/usr/local/share/applications"
  else
    BIN_DIR="${BIN_OVERRIDE:-$HOME/.local/bin}"
    LIB_DIR="${LIB_OVERRIDE:-$HOME/.local/lib/continuity}"
    APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  fi
}

# ---------------------------------------------------------------------------
#  preflight
# ---------------------------------------------------------------------------
preflight() {
  step "Preflight"
  continuity_have bash || die "bash is required"
  if [ "$MODE" = "system" ] && [ "$(id -u)" != "0" ]; then
    die "--system needs root: sudo $SELF --system"
  fi

  local f
  for f in "${ENGINE_FILES[@]}"; do
    [ -r "$SRC_DIR/bin/$f" ] || die "bin/$f is missing — this is not a complete checkout"
  done
  ok "source tree complete ($SRC_DIR)"
  if [ "$MODE" = "user" ] && [ "$(id -u)" = "0" ]; then
    warn "--user as root installs into /root/.local; use --system for every user"
  fi

  local arch pretty
  arch="$(uname -m)"
  if [ "$arch" != "x86_64" ]; then
    warn "host architecture is $arch; Proton and umu-run are x86_64 artefacts"
  fi
  # shellcheck disable=SC1091
  pretty="$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}" )"
  ok "distribution: $pretty ($(continuity_family))"
  say "install target: $BIN_DIR"
}

# Install a text script with Unix line endings. A Windows checkout can leave
# CRLF in a shebang, and the kernel then looks for an interpreter literally
# called "bash\r" — the installed command would fail with "No such file or
# directory" while the source file looks perfectly fine.
install_text() {
  local src="$1" dst="$2" mode="$3" tmp
  if [ "$DRY_RUN" = "1" ]; then
    printf '  %s+ install -m %s %s %s%s\n' "$C_DIM" "$mode" "$src" "$dst" "$C_RESET" >&2
    return 0
  fi
  tmp="$(mktemp)"
  sed 's/\r$//' "$src" >"$tmp"
  install -m "$mode" "$tmp" "$dst"
  rm -f -- "$tmp"
}

# Did this project write the file? Every file this project installs names
# ContinuityOS somewhere (the scripts in their header, the desktop entry in its
# Comment and X- key), so a foreign `proton` in the target directory is never
# clobbered — but our own files are simply replaced on re-install.
is_ours() {
  [ -f "$1" ] && grep -q 'ContinuityOS' "$1" 2>/dev/null
}

guard_target() {
  local target="$1"
  [ -e "$target" ] || return 0
  is_ours "$target" && return 0
  [ "$FORCE" = "1" ] && { warn "overwriting $target (--force)"; return 0; }
  die "$target already exists and was not installed by this project — move it, or use --bin/--lib to choose another directory"
}

# ---------------------------------------------------------------------------
#  prerequisites
# ---------------------------------------------------------------------------
deps_command() {
  local fam pkgs=() t
  fam="$(continuity_family)"
  for t in "$@"; do
    case "$fam:$t" in
      arch:python3) pkgs+=(python) ;;
      *)            pkgs+=("$t") ;;
    esac
  done
  case "$fam" in
    arch)   printf 'sudo pacman -S --needed --noconfirm %s' "${pkgs[*]}" ;;
    debian) printf 'sudo apt-get install -y %s' "${pkgs[*]}" ;;
    fedora) printf 'sudo dnf install -y %s' "${pkgs[*]}" ;;
    suse)   printf 'sudo zypper --non-interactive install %s' "${pkgs[*]}" ;;
    *)      return 1 ;;
  esac
}

check_deps() {
  step "Prerequisites"
  local missing=() t cmd

  for t in python3 tar; do continuity_have "$t" || missing+=("$t"); done
  if ! continuity_have curl && ! continuity_have wget; then missing+=(curl); fi

  if [ "${#missing[@]}" -gt 0 ]; then
    cmd="$(deps_command "${missing[@]}" 2>/dev/null || true)"
    if [ "$WITH_DEPS" = "1" ] && [ -n "$cmd" ]; then
      say "$cmd"
      run bash -c "$cmd" || die "could not install: ${missing[*]}"
    else
      warn "missing: ${missing[*]}"
      [ -n "$cmd" ] && printf '  fix: %s\n' "$cmd" >&2
      [ "$DRY_RUN" = "1" ] || die "install the prerequisites above (or re-run with --with-deps) and try again"
    fi
  else
    ok "python3, tar and a downloader are present"
  fi
  # zstd is deliberately not required: umu-run does not use it, and the only
  # consumer (continuity-prefix export) falls back to gzip on its own.
}

# ---------------------------------------------------------------------------
#  the commands
# ---------------------------------------------------------------------------
install_engine() {
  step "Installing the engine"
  run install -d -m 0755 "$BIN_DIR" "$LIB_DIR"

  local f target
  for f in "${ENGINE_FILES[@]}"; do
    target="$BIN_DIR/$f"
    guard_target "$target"
    install_text "$SRC_DIR/bin/$f" "$target" 0755
  done
  guard_target "$LIB_DIR/continuity-common.sh"
  install_text "$SRC_DIR/lib/continuity-common.sh" "$LIB_DIR/continuity-common.sh" 0644
  ok "${ENGINE_FILES[*]} -> $BIN_DIR"

  local conf
  if [ "$MODE" = "system" ]; then
    # A system install must not creep into root's home; new users get the same
    # defaults the distribution installer uses.
    conf="/etc/skel/.config/continuity/environment.conf"
  else
    conf="${XDG_CONFIG_HOME:-$HOME/.config}/continuity/environment.conf"
  fi
  if [ -e "$conf" ]; then
    say "keeping the existing configuration: $conf"
  else
    run install -d -m 0755 "$(dirname "$conf")"
    run install -m 0644 "$SRC_DIR/config/environment.conf" "$conf"
    ok "wrote $conf"
  fi
}

# ---------------------------------------------------------------------------
#  umu-run
# ---------------------------------------------------------------------------
fetch_url() {
  local url="$1" out="$2"
  if continuity_have curl; then
    curl -fsSL --max-time 900 "$url" -o "$out"
  elif continuity_have wget; then
    wget -qO "$out" "$url"
  else
    return 1
  fi
}

install_umu_from() {
  local src="$1"
  [ -f "$src" ] || die "no such file: $src"
  run install -d -m 0755 "$BIN_DIR"
  run install -m 0755 "$src" "$BIN_DIR/umu-run"
  ok "installed $BIN_DIR/umu-run"
}

download_umu() {
  local api json tag name digest url archive found actual
  api="https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest"

  if [ "$DRY_RUN" = "1" ]; then
    printf '  %s+ download the latest umu-launcher zipapp (%s) -> %s/umu-run%s\n' \
      "$C_DIM" "$api" "$BIN_DIR" "$C_RESET" >&2
    UMU_PLANNED=1
    return 0
  fi

  WORK_TMP="$(mktemp -d)"
  json="$WORK_TMP/release.json"
  say "reading $api"
  fetch_url "$api" "$json" || die "could not read the umu-launcher release list (no network?)"

  local meta
  meta="$(python3 - "$json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
tag = d.get("tag_name") or ""
for a in d.get("assets", []):
    if a.get("name", "").endswith("-zipapp.tar"):
        print(tag)
        print(a["name"])
        print(a.get("digest") or "")
        break
PY
)" || die "could not parse $api"

  tag="$(printf '%s\n' "$meta" | sed -n 1p)"
  name="$(printf '%s\n' "$meta" | sed -n 2p)"
  digest="$(printf '%s\n' "$meta" | sed -n 3p)"
  [ -n "$name" ] || die "the latest umu-launcher release has no zipapp archive"
  ok "latest release: ${tag:-unknown} ($name)"

  url="https://github.com/Open-Wine-Components/umu-launcher/releases/download/$tag/$name"
  archive="$WORK_TMP/umu.tar"
  say "downloading $url"
  fetch_url "$url" "$archive" || die "download failed: $url"

  if [ -n "$digest" ]; then
    if continuity_have sha256sum; then
      actual="sha256:$(sha256sum "$archive" | cut -d' ' -f1)"
      [ "$actual" = "$digest" ] || die "checksum mismatch for $name (expected $digest, got $actual)"
      ok "sha256 verified"
    else
      warn "sha256sum is missing, so the download could not be verified"
    fi
  else
    warn "the release publishes no checksum, so the download could not be verified"
  fi

  tar -xf "$archive" -C "$WORK_TMP" || die "could not unpack $name"
  found="$(find "$WORK_TMP" -type f -name umu-run -print -quit 2>/dev/null || true)"
  [ -n "$found" ] || die "$name does not contain umu-run"
  install_umu_from "$found"

  if "$BIN_DIR/umu-run" --version >/dev/null 2>&1; then
    ok "umu-run $("$BIN_DIR/umu-run" --version 2>/dev/null | head -n1)"
  else
    warn "$BIN_DIR/umu-run did not answer --version; 'proton check' will report it"
  fi
}

ensure_umu() {
  step "Proton runtime launcher (umu-run)"
  if [ -n "$ENGINE_PATH" ]; then
    [ -x "$ENGINE_PATH" ] || die "--engine '$ENGINE_PATH' is not an executable file"
    install_umu_from "$ENGINE_PATH"
    return 0
  fi

  local existing
  existing="$(command -v umu-run 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    ok "already available: $existing"
    return 0
  fi
  if [ -x "$BIN_DIR/umu-run" ]; then
    ok "already installed: $BIN_DIR/umu-run"
    return 0
  fi
  if [ "$NO_DOWNLOAD" = "1" ]; then
    warn "--no-download: umu-run is not installed; 'proton check' reports it until you add one"
    return 0
  fi
  download_umu
}

install_wine() {
  local cmd
  cmd="$(continuity_pkg_command wine wine32 2>/dev/null || true)"
  step "Wine (for .msi, .lnk and --native)"
  if continuity_have wine; then ok "already installed: $(command -v wine)"; return 0; fi
  [ -n "$cmd" ] || die "do not know how to install Wine on $(continuity_family)"
  say "$cmd"
  run bash -c "$cmd" || warn "Wine did not install cleanly; the Proton engine still works"
}

# ---------------------------------------------------------------------------
#  desktop integration (.exe double-click)
# ---------------------------------------------------------------------------
install_desktop() {
  [ "$DESKTOP" = "1" ] || return 0
  step "Windows .exe handler"
  local file="$APP_DIR/continuity-wine.desktop" tmp t

  if [ "$MODE" = "system" ]; then
    # A system-wide install must not rewrite the root user's MIME database.
    run install -d -m 0755 "$APP_DIR"
    tmp="$(mktemp)"
    write_desktop_entry "$tmp"
    guard_target "$file"
    run install -m 0644 "$tmp" "$file"
    rm -f -- "$tmp"
    ok "registered the handler for every user (appears in \"Open with\")"
    return 0
  fi

  run install -d -m 0755 "$APP_DIR"
  tmp="$(mktemp)"
  write_desktop_entry "$tmp"
  guard_target "$file"
  run install -m 0644 "$tmp" "$file"
  rm -f -- "$tmp"

  if continuity_have xdg-mime; then
    for t in "${MIME_TYPES[@]}"; do
      run xdg-mime default continuity-wine.desktop "$t" || \
        { warn "xdg-mime could not set the default for $t"; break; }
    done
    ok "double-clicking a .exe now opens it in Proton"
  else
    warn "xdg-mime is not installed; the handler exists but is not the default"
  fi
  continuity_have update-desktop-database && \
    run update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
}

write_desktop_entry() {
  local out="$1"
  cat >"$out" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Windows Executable
GenericName=Universal Windows Compatibility Engine
Comment=Run a Windows program in its own isolated Proton prefix (ContinuityOS engine)
X-ContinuityOS-Engine=true
Exec=$BIN_DIR/proton %f
TryExec=$BIN_DIR/proton
Icon=application-x-executable
Terminal=false
StartupNotify=true
Categories=Game;Utility;Wine;
Keywords=exe;windows;wine;proton;umu;game;setup;
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/x-ms-shortcut;application/vnd.microsoft.portable-executable;application/x-msi;
EOF
}

# ---------------------------------------------------------------------------
#  PATH
# ---------------------------------------------------------------------------
ensure_path() {
  step "PATH"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ok "$BIN_DIR is already on PATH"; return 0 ;;
  esac

  local export_line="export PATH=\"$BIN_DIR:\$PATH\""

  if [ "$WRITE_PATH" != "1" ]; then
    warn "add this to your shell profile: $export_line"
    return 0
  fi
  if [ "$MODE" = "system" ]; then
    warn "/usr/local/bin is normally on PATH already; open a new terminal if not"
    return 0
  fi

  # Debian/Ubuntu ship a ~/.profile that adds ~/.local/bin itself, and shells
  # started from a desktop session often pick it up from there. Only edit a file
  # when nothing already does the job.
  local rc
  for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
    [ -r "$rc" ] || continue
    if grep -qF '.local/bin' "$rc" 2>/dev/null; then
      ok "$rc already adds ~/.local/bin; open a new terminal to pick it up"
      return 0
    fi
  done

  rc="$HOME/.profile"
  if [ "$DRY_RUN" = "1" ]; then
    printf '  %s+ append the PATH block to %s%s\n' "$C_DIM" "$rc" "$C_RESET" >&2
    return 0
  fi
  {
    printf '\n# >>> continuity engine (managed by install.sh) >>>\n'
    printf '%s\n' "$export_line"
    printf '# <<< continuity engine (managed by install.sh) <<<\n'
  } >>"$rc"
  ok "added $BIN_DIR to PATH in $rc (open a new terminal, or run: $export_line)"
}

# ---------------------------------------------------------------------------
#  verify
# ---------------------------------------------------------------------------
verify() {
  [ "$DRY_RUN" = "1" ] && return 0
  step "Verifying"
  local out probe

  if out="$(PATH="$BIN_DIR:$PATH" "$BIN_DIR/proton" version 2>&1)"; then
    ok "the installed command runs:"
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  else
    warn "the installed command did not run: $out"
    return 0
  fi

  # --print-env resolves the whole launch environment without starting anything,
  # and a throwaway prefix root keeps the check out of the real one.
  WORK_TMP="${WORK_TMP:-$(mktemp -d)}"
  probe="$WORK_TMP/probe.exe"
  : >"$probe"
  if out="$(PATH="$BIN_DIR:$PATH" CONTINUITY_PREFIX_ROOT="$WORK_TMP/prefixes" \
            "$BIN_DIR/proton" --print-env "$probe" 2>&1)"; then
    case "$out" in
      *CONTINUITY_PREFIX_DIR=*)
        ok "the launcher resolves its prefix: $(printf '%s\n' "$out" | sed -n 's/^CONTINUITY_PREFIX_DIR=//p')" ;;
      *) warn "the launcher did not report a prefix" ;;
    esac
  else
    warn "the launcher could not resolve a launch environment: $out"
  fi
}

summary() {
  step "Done"
  say "command:   $BIN_DIR/proton"
  if [ "$MODE" = "system" ]; then
    say "prefixes:  ~/.local/share/universal-prefixes (one per user)"
    say "config:    /etc/skel/.config/continuity/environment.conf (new users)"
  else
    say "prefixes:  $CONTINUITY_PREFIX_ROOT"
    say "config:    $CONTINUITY_CONFIG_DIR/environment.conf"
  fi
  printf '\n' >&2
  say "  $BIN_DIR/proton check                      what is missing on this machine"
  say "  $BIN_DIR/proton ~/Downloads/GameSetup.exe  run a Windows program"
  say "  $BIN_DIR/proton list                       your prefixes"
  say "  $BIN_DIR/proton uninstall                  remove the engine"
  printf '\n' >&2
  if ! continuity_have umu-run && [ ! -x "$BIN_DIR/umu-run" ] && [ "$UMU_PLANNED" = "0" ]; then
    warn "umu-run is missing: launches will fail until it is installed (re-run without --no-download)"
  fi
}

# ---------------------------------------------------------------------------
#  uninstall
# ---------------------------------------------------------------------------
uninstall_engine() {
  local args=()
  [ "$PURGE" = "1" ] && args+=(--purge)
  [ "$ASSUME_YES" = "1" ] && args+=(--yes)

  step "Uninstall"
  if [ -x "$BIN_DIR/proton" ] && is_ours "$BIN_DIR/proton"; then
    run "$BIN_DIR/proton" uninstall "${args[@]+"${args[@]}"}"
    # `proton uninstall` only manages $HOME; the root-level extras are this
    # script's to remove.
    if [ "$MODE" = "system" ]; then
      run rm -f -- /etc/skel/.config/continuity/environment.conf
    fi
    run rmdir --ignore-fail-on-non-empty "$LIB_DIR" 2>/dev/null || true
    return 0
  fi
  # The command is already gone: remove the rest by hand.
  local f removed=0
  for f in "${ENGINE_FILES[@]}"; do
    if [ -e "$BIN_DIR/$f" ]; then run rm -f -- "$BIN_DIR/$f"; removed=1; fi
  done
  if [ -e "$LIB_DIR/continuity-common.sh" ]; then
    run rm -f -- "$LIB_DIR/continuity-common.sh"; removed=1
  fi
  run rm -f -- "$APP_DIR/continuity-wine.desktop"
  [ "$MODE" = "system" ] && \
    run rm -f -- /etc/skel/.config/continuity/environment.conf
  # The library directory is ours; leave it behind only if something else is in it.
  run rmdir --ignore-fail-on-non-empty "$LIB_DIR" 2>/dev/null || true
  if [ "$removed" = "0" ]; then
    say "nothing to remove in $BIN_DIR"
  else
    ok "removed the engine from $BIN_DIR"
  fi
  [ "$PURGE" = "1" ] && run rm -rf -- "$CONTINUITY_CONFIG_DIR" "$CONTINUITY_PREFIX_ROOT"
  return 0
}

# ---------------------------------------------------------------------------
#  main
# ---------------------------------------------------------------------------
resolve_paths

if [ "$UNINSTALL" = "1" ]; then
  [ "$MODE" = "system" ] && [ "$(id -u)" != "0" ] && \
    die "--system --uninstall needs root: sudo $SELF --system --uninstall"
  uninstall_engine
  exit 0
fi

preflight
check_deps
install_engine
ensure_umu
if [ "$WITH_WINE" = "1" ]; then install_wine; fi
install_desktop
ensure_path
verify
summary
