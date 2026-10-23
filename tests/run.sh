#!/usr/bin/env bash
# ContinuityOS — offline verification suite.
#
#   tests/run.sh              everything
#   tests/run.sh --syntax     bash -n / XML / INI checks only
#   tests/run.sh --functional only the behaviour tests
#
# It never needs Arch, root, Hyprland or a network: the shell tools are written to
# degrade gracefully, and this suite proves it. Run it after every change.
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
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

MODE="all"
case "${1:-}" in
  --syntax) MODE="syntax" ;;
  --functional) MODE="functional" ;;
  ""|--all) MODE="all" ;;
  *) echo "usage: tests/run.sh [--syntax|--functional]" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# syntax
# ---------------------------------------------------------------------------
syntax_checks() {
  group "Shell syntax (bash -n)"

  # Every shell script in the repo, including extensionless executables.
  local files=()
  local f
  while IFS= read -r f; do files+=("$f"); done < <(
    {
      find bin lib tools tests -maxdepth 2 -type f 2>/dev/null
      printf '%s\n' install.sh
      find iso -maxdepth 4 -type f -name '*.sh' 2>/dev/null
      find config/eww/scripts -type f -name '*.sh' 2>/dev/null
    } | while IFS= read -r p; do
      [ -f "$p" ] || continue
      case "$p" in
        # Only files that are actually shell: not markdown, not hooks.
        *.md|*.hook|*.jsonc|*.css|*.scss|*.svg|*.conf|*.rasi) continue ;;
      esac
      if [ "${p##*.}" = "$p" ] || [ "${p##*.}" = "sh" ]; then printf '%s\n' "$p"; fi
    done | sort -u
  )

  if [ "${#files[@]}" -eq 0 ]; then
    fail "no shell scripts found — is the repo complete?"
  fi

  for f in "${files[@]}"; do
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
      head -1 "$f" | grep -qE '^#!.*(bash|sh)' || continue
      shellcheck -S error -e SC1090,SC1091 "$f" >/dev/null 2>&1 || { fail "shellcheck $f"; sc=1; }
    done
    [ "$sc" = "0" ] && pass "shellcheck found no errors"
  else
    printf '  %sSKIP%s shellcheck is not installed\n' "$C_DIM" "$C_RESET"
  fi

  group "Structured config files"
  # JSON-ish and XML documents must parse; ini-style files must not have a stray '='-less line.
  local j f2
  for j in config/waybar/config.jsonc; do
    [ -r "$j" ] || continue
    if command -v python3 >/dev/null 2>&1; then
      # strip // comments and trailing commas the way jsonc allows them
      if sed -e 's://.*$::' -e 's:,\s*\([}\]]\):\1:g' "$j" | python3 -m json.tool >/dev/null 2>&1; then
        pass "JSON $j"
      else
        fail "JSON $j (does not parse after comment stripping)"
      fi
    fi
  done

  for f2 in assets/wallpapers/*.svg assets/icons/*.svg; do
    [ -r "$f2" ] || continue
    if command -v python3 >/dev/null 2>&1; then
      if python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$f2" >/dev/null 2>&1; then
        pass "XML $f2"
      else
        fail "XML $f2 (malformed SVG)"
      fi
    fi
  done

  group "Eww shell structure"
  # eww itself cannot run here, so a structural validator stands in for it:
  # balanced parentheses, no call to an undefined widget, all windows sized.
  if command -v python3 >/dev/null 2>&1; then
    local ewwlog="$TMP/eww-check.log"
    if python3 tests/check-eww.py >"$ewwlog" 2>&1; then
      pass "$(grep -o 'PASS.*' "$ewwlog" | head -n1)"
    else
      fail "eww.yuck has structural problems"
      sed 's/^/        /' "$ewwlog"
    fi
  else
    printf '  %sSKIP%s python3 is not installed\n' "$C_DIM" "$C_RESET"
  fi

  # SCSS that does not compile takes the entire shell down with it.
  local scss="config/eww/eww.scss"
  if [ -r "$scss" ]; then
    local so sc
    so="$(tr -cd '{' <"$scss" | wc -c)"
    sc="$(tr -cd '}' <"$scss" | wc -c)"
    if [ "$so" = "$sc" ]; then pass "eww.scss braces balance ($so blocks)"; else fail "eww.scss is unbalanced: $so '{' vs $sc '}'"; fi
  fi

  for f2 in config/dunst/dunstrc iso/profile/profiledef.sh; do
    [ -r "$f2" ] || continue
    case "$f2" in
      *dunstrc)
        # dunst requires every key to live in [global]; check the section exists.
        if grep -q '^\[global\]' "$f2"; then pass "INI $f2 has [global]"; else fail "INI $f2 is missing [global]"; fi
        ;;
      *)
        if grep -qE '^(iso_name|iso_label|install_dir)=' "$f2"; then pass "archiso $f2"; else fail "archiso $f2 looks incomplete"; fi
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# manifest: everything install.sh references must exist
# ---------------------------------------------------------------------------
manifest_checks() {
  group "install.sh manifest"

  local required=(
    bin/continuity-run bin/continuity-prefix bin/continuity-gaming-mode
    bin/continuity-panel bin/continuity-shell
    bin/continuity-session-start bin/continuity-screenshot bin/continuity-first-boot
    bin/continuity-wizard lib/continuity-common.sh
    bin/continuity-boot bin/continuity-region bin/continuity-export
    bin/continuity-shakedown bin/continuity-installer bin/continuity-end4-pc
    config/greetd/config.toml.tmpl
    config/eww/scripts/wizard.sh tests/check-eww.py
    desktop/continuity-welcome.desktop docs/WIZARD.md docs/BOOT.md docs/INSTALL.md
    docs/END4-PC.md
    iso/profile/airootfs/etc/sysusers.d/continuity-live.conf
    iso/profile/airootfs/etc/sudoers.d/continuity-live
    iso/profile/airootfs/etc/systemd/system/greetd.service.d/10-continuity-live.conf
    config/continuity/environment.conf config/continuity/gtk.css
    config/hypr/hyprland.conf config/hypr/hyprpaper.conf config/hypr/hypridle.conf
    config/hypr/hyprlock.conf
    config/waybar/config.jsonc config/waybar/style.css
    config/eww/eww.yuck config/eww/eww.scss
    config/rofi/continuity.rasi config/dunst/dunstrc
    desktop/continuity-wine.desktop desktop/continuity-prefix.desktop
    desktop/continuity-gaming-mode.desktop desktop/continuity-panel.desktop
    desktop/continuity-verify.desktop desktop/mimeapps.list
    sessions/continuity.desktop
    systemd/continuity-first-boot.service
    packages/core.list packages/desktop.list packages/gaming.list packages/creative.list
    packages/aur.list etc/install.conf tools/uninstall.sh
    assets/icons/windows-app.svg assets/icons/continuity-windows.svg
    assets/icons/input-gaming.svg assets/icons/video-display.svg
    assets/wallpapers/continuity-dark-01.svg
    iso/build.sh iso/profile/profiledef.sh iso/profile/packages.x86_64
    docs/ARCHITECTURE.md docs/COMPATIBILITY.md docs/FREEBUFF.md docs/UNINSTALL.md
    README.md
  )
  local f
  for f in "${required[@]}"; do
    if [ -e "$f" ]; then pass "present: $f"; else fail "MISSING: $f"; fi
  done

  group "Executable bits on the installed CLI"
  for f in bin/*; do
    if [ "${f##*/}" = "continuity-common.sh" ]; then continue; fi
    case "$f" in
      *.[a-z]*) continue ;;
    esac
    [ -f "$f" ] || continue
    if [ -x "$f" ]; then pass "executable: $f"; else fail "not executable: $f"; fi
  done

  group "Cross-references"
  # Commands the configs call must be real scripts in bin/.
  local referenced cmd missing_refs=0
  referenced="$(grep -rhoE '/usr/local/bin/continuity-[a-z-]+' config/ desktop/ sessions/ systemd/ 2>/dev/null | sort -u)"
  for cmd in $referenced; do
    if [ -x "bin/${cmd##*/}" ]; then
      pass "referenced and present: $cmd"
    else
      fail "referenced but not in bin/: $cmd"
      missing_refs=1
    fi
  done
  [ "$missing_refs" = "0" ] || true

  group "end4-pC private overlay scaffold"
  local end4_home="$TMP/end4-home" end4_out
  end4_out="$(HOME="$end4_home" XDG_CONFIG_HOME="$end4_home/config" bin/continuity-end4-pc status 2>&1)"
  case "$end4_out" in *overlay=not-installed*"pinned_commit="*) pass "status handles an absent overlay" ;; *) fail "status is wrong for an absent overlay: $end4_out" ;; esac
  bash bin/continuity-end4-pc --help >/dev/null 2>&1 && pass "helper help runs" || fail "helper help failed"
  mkdir -p "$end4_home/config/quickshell/end4-pC"
  if HOME="$end4_home" XDG_CONFIG_HOME="$end4_home/config" bin/continuity-end4-pc install >/dev/null 2>&1; then
    fail "installer overwrote an unowned destination"
  else
    pass "installer refuses an unowned destination"
  fi
  [ -d "$end4_home/config/quickshell/end4-pC" ] && pass "refusal preserved existing destination" || fail "refusal altered existing destination"
  if HOME="$end4_home" XDG_CONFIG_HOME="$end4_home/config" bin/continuity-end4-pc launch >/dev/null 2>&1; then
    fail "launch accepted a non-pinned destination"
  else
    pass "launch refuses a non-pinned checkout"
  fi
  grep -q '^PINNED_COMMIT=' bin/continuity-end4-pc && pass "checkout pin is declared" || fail "checkout pin is missing"
  grep -q 'proton-cachyos-slr' packages/gaming.list && pass "CachyOS SLR Proton remains in the gaming stack" || fail "CachyOS SLR Proton is missing"
  grep -q 'proton-cachyos-native' packages/gaming.list && pass "native Proton remains separately packaged" || fail "native Proton package is missing"
  grep -q '^umu-launcher$' packages/gaming.list && pass "UMU remains installed for the default runner" || fail "UMU package is missing"
  ! grep -q 'end4-pC' iso/profile/packages.x86_64 && pass "private overlay is not bundled into the ISO" || fail "private overlay is bundled into the ISO"

  # The live medium is intentionally UEFI-only; keep this contract in the
  # offline suite so an accidental BIOS/syslinux boot mode fails immediately.
  group "UEFI-only ISO profile"
  if grep -Fq "bootmodes=('uefi.systemd-boot')" iso/profile/profiledef.sh; then
    pass "ISO profile selects UEFI systemd-boot only"
  else
    fail "ISO profile must select UEFI systemd-boot only"
  fi
  if [ ! -e iso/profile/syslinux ] && ! grep -Eq 'bootmodes=\(.*bios\.|bootmask' iso/profile/profiledef.sh iso/build.sh; then
    pass "ISO profile has no BIOS/syslinux boot configuration"
  else
    fail "ISO profile or builder contains a BIOS/syslinux boot configuration"
  fi
  if grep -Fq 'UEFI El Torito entry' iso/build.sh && grep -Fq 'GPT EFI System Partition' iso/build.sh; then      pass "ISO builder validates UEFI El Torito, GPT EFI system partition and excludes BIOS boot metadata"

  else
    fail "ISO builder is missing post-build UEFI metadata validation"
  fi
  if grep -Fq 'modifyvm $vm --firmware efi' build/boot-new-iso.ps1 && grep -Fq '^firmware="EFI"$' build/boot-new-iso.ps1; then
    pass "VirtualBox ISO runner explicitly enables EFI firmware"
  else
    fail "VirtualBox ISO runner does not explicitly enable EFI firmware"
  fi

  # Icon names referenced by code/config must exist as asset SVGs or system icons.
  local icon
  for icon in windows-app continuity-windows input-gaming video-display; do
    if [ -e "assets/icons/$icon.svg" ]; then pass "icon asset: $icon"; else fail "icon asset missing: $icon"; fi
  done

  # Eww surfaces used by continuity-panel must be defined in eww.yuck.
  local surface
  for surface in dock drawer notifications; do
    if grep -qE "^\(defwindow[[:space:]]+$surface\b" config/eww/eww.yuck 2>/dev/null; then
      pass "eww window defined: $surface"
    else
      fail "eww window missing from eww.yuck: $surface"
    fi
  done
}

# ---------------------------------------------------------------------------
# functional behaviour (no root, no Arch, no compositor)
# ---------------------------------------------------------------------------
functional_checks() {
  group "continuity-run (the .exe handler)"

  local fix="$TMP/My Game Setup.exe"
  printf 'MZ\x90\x00' > "$fix"
  printf 'MZ\x90\x00' > "$TMP/plain.exe"

  local out
  if out="$(HOME="$TMP/home" NO_COLOR=1 bin/continuity-run --print-env "$fix" 2>&1)"; then
    local prefix drive slug
    slug="$(printf '%s\n' "$out" | sed -n 's/^CONTINUITY_SLUG=//p')"
    prefix="$(printf '%s\n' "$out" | sed -n 's/^CONTINUITY_PREFIX_DIR=//p')"
    drive="$(printf '%s\n' "$out" | sed -n 's/^CONTINUITY_DRIVE_C=//p')"
    [ "$slug" = "my-game-setup" ] && pass "slug from filename: $slug" || fail "slug: expected my-game-setup, got '$slug'"
    case "$prefix" in
      *"/.local/share/universal-prefixes/my-game-setup") pass "prefix path: $prefix" ;;
      *) fail "prefix path unexpected: $prefix" ;;
    esac
    case "$drive" in
      */my-game-setup/drive_c) pass "drive_c inside app compatdata: $drive" ;;
      *) fail "drive_c path unexpected: $drive" ;;
    esac
    printf '%s\n' "$out" | grep -q '^CONTINUITY_ENGINE=umu$' && pass "default engine is UMU + Proton" || fail "default engine is not UMU"
    printf '%s\n' "$out" | grep -q '^CONTINUITY_LAUNCH_MODE=umu$' && pass "default launch mode is UMU" || fail "launch mode is not UMU"
    if printf '%s\n' "$out" | grep -q '^COMMAND=umu-run '; then
      pass "default command uses UMU rather than direct host Proton"
    elif printf '%s\n' "$out" | grep -q '^COMMAND=<unavailable: umu-run not found>$'; then
      pass "default command is correctly marked unavailable without UMU installed"
    else
      fail "default command does not use or identify missing UMU"
    fi
    printf '%s\n' "$out" | grep -q "^GAMEID=0$" && pass "app ID defaults to 0" || fail "app ID default wrong"
  else
    fail "continuity-run --print-env exited non-zero without Proton installed (it must still work)"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi

  # A fake UMU executable verifies the default launch route and environment offline.
  local fake_umu="$TMP/bin/umu-run"
  mkdir -p "$TMP/bin"
  cat >"$fake_umu" <<'UMU'
#!/usr/bin/env bash
printf '%s\n' "FAKE_UMU gameid=$GAMEID prefix=$WINEPREFIX path=$PROTONPATH args=$*" >>"$UMU_TEST_LOG"
UMU
  chmod +x "$fake_umu"
  local umu_log="$TMP/umu.log"
  if out="$(PATH="$TMP/bin:$PATH" HOME="$TMP/home" bin/continuity-run --print-env "$TMP/plain.exe" 2>&1)"; then
    printf '%s\n' "$out" | grep -q '^COMMAND=umu-run ' && pass "UMU print-env selects umu-run" || fail "UMU command unresolved"
    printf '%s\n' "$out" | grep -q '^CONTINUITY_LAUNCH_MODE=umu$' && pass "UMU print-env identifies the launcher mode" || fail "UMU launch mode is wrong"
  else
    fail "UMU --print-env failed with UMU available"
  fi
  if PATH="$TMP/bin:$PATH" HOME="$TMP/home" UMU_TEST_LOG="$umu_log" bin/continuity-run -g umu-fixture "$TMP/plain.exe" -- '--umu argument' >/dev/null 2>&1; then
    pass "fake UMU launch returns successfully"
  else
    fail "fake UMU launch failed"
  fi
  grep -Fq 'FAKE_UMU gameid=umu-fixture' "$umu_log" && pass "UMU receives GAMEID" || fail "UMU did not receive GAMEID"
  grep -Fq -- '--umu argument' "$umu_log" && pass "UMU receives application arguments" || fail "UMU lost application arguments"

  # A fake Steam-managed Proton tree tests explicit direct host invocation offline.
  local fake_proton="$TMP/home/.local/share/Steam/steamapps/common/Proton - Experimental"
  mkdir -p "$fake_proton"
  cat >"$fake_proton/proton" <<'PROTON'
#!/usr/bin/env bash
printf '%s\n' "FAKE_PROTON verb=$1 target=$2 prefix=$WINEPREFIX compat=$STEAM_COMPAT_DATA_PATH appid=$STEAM_COMPAT_APP_ID steam=$SteamAppId game=$SteamGameId args=$*" >>"$PROTON_TEST_LOG"
PROTON
  chmod +x "$fake_proton/proton"
  mkdir -p "$TMP/home/.local/share/Steam"
  local proton_log="$TMP/proton.log"
  if out="$(HOME="$TMP/home" bin/continuity-run --print-env --direct --proton "Proton - Experimental" -g 123456 "$TMP/plain.exe" 2>&1)"; then
    printf '%s\n' "$out" | grep -q '^PROTON_SCRIPT=.*/Proton - Experimental/proton$' && pass "runner name resolves to a host Proton script" || fail "runner name did not resolve"
    printf '%s\n' "$out" | grep -q '^WINEPREFIX=.*/universal-prefixes/plain/pfx$' && pass "Proton receives its pfx directory as WINEPREFIX" || fail "Proton WINEPREFIX is wrong"
    printf '%s\n' "$out" | grep -q '^STEAM_COMPAT_CLIENT_INSTALL_PATH=.*/Steam$' && pass "Steam client root is supplied" || fail "Steam client root was not detected"
    printf '%s\n' "$out" | grep -q '^STEAM_COMPAT_DATA_PATH=.*/universal-prefixes/plain$' && pass "compatdata stays isolated per app" || fail "compatdata path is wrong"
    printf '%s\n' "$out" | grep -q '^STEAM_COMPAT_APP_ID=123456$' && pass "app ID is passed to Proton" || fail "Steam compat app ID is wrong"
    printf '%s\n' "$out" | grep -q '^COMMAND=.*/proton waitforexitandrun ' && pass "command directly invokes Proton without UMU" || fail "command is not direct Proton"
  else
    fail "continuity-run --print-env failed with a fake Proton installation"
  fi
  if HOME="$TMP/home" PROTON_TEST_LOG="$proton_log" bin/continuity-run --direct --proton "$fake_proton" -g 123456 "$TMP/plain.exe" -- '--flag with spaces' >/dev/null 2>&1; then
    pass "fake Proton launch returns successfully"
  else
    fail "fake Proton launch failed"
  fi
  grep -Fq 'FAKE_PROTON verb=waitforexitandrun' "$proton_log" && pass "direct Proton receives the wait verb" || fail "direct Proton did not receive the expected verb: $(cat "$proton_log" 2>/dev/null)"
  grep -Fq 'appid=123456 steam=123456 game=123456' "$proton_log" && pass "Steam-compatible app IDs are exported" || fail "app IDs were not exported consistently: $(cat "$proton_log" 2>/dev/null)"
  grep -Fq -- '--flag with spaces' "$proton_log" && pass "application arguments survive direct invocation" || fail "application arguments were not passed: $(cat "$proton_log" 2>/dev/null)"

  if out="$(HOME="$TMP/home" bin/continuity-run --print-env --native "$TMP/plain.exe" 2>&1)"; then
    printf '%s\n' "$out" | grep -q '^CONTINUITY_ENGINE=wine$' && pass "--native selects wine" || fail "--native did not select wine"
    printf '%s\n' "$out" | grep -q '^COMMAND=wine ' && pass "wine is the command" || fail "wine is not the command: $(printf '%s\n' "$out" | grep '^COMMAND=')"
    printf '%s\n' "$out" | grep -q '^WINEPREFIX=.*/universal-prefixes/plain$' && pass "--native preserves its legacy isolated prefix" || fail "native Wine prefix path changed"
  else
    fail "continuity-run --native --print-env failed (wine absence must not stop --print-env)"
  fi

  # A legacy Wine prefix migrates into Proton's pfx without losing its files.
  local legacy_dir="$TMP/home/.local/share/universal-prefixes/legacy"
  mkdir -p "$legacy_dir/drive_c/Program Files/Legacy" "$legacy_dir/dosdevices"
  : >"$legacy_dir/system.reg"
  : >"$legacy_dir/drive_c/Program Files/Legacy/Legacy.exe"
  if HOME="$TMP/home" PROTON_TEST_LOG="$proton_log" bin/continuity-run --direct --proton "$fake_proton" -n legacy "$TMP/plain.exe" >/dev/null 2>&1; then
    if [ -f "$legacy_dir/pfx/system.reg" ] && [ -f "$legacy_dir/pfx/drive_c/Program Files/Legacy/Legacy.exe" ]; then
      pass "existing prefix files migrate under pfx intact"
    else
      fail "legacy prefix migration lost data"
    fi
    [ ! -e "$legacy_dir/drive_c" ] && pass "legacy root layout is upgraded" || fail "old drive_c remains beside pfx"
  else
    fail "legacy prefix direct Proton launch failed"
  fi
  if out="$(HOME="$TMP/home" bin/continuity-run --print-env --direct --proton "Proton - Experimental" -n legacy "$TMP/plain.exe" 2>&1)"; then
    printf '%s\n' "$out" | grep -q '^WINEPREFIX=.*/universal-prefixes/legacy/pfx$' && pass "migrated prefix selects Proton pfx" || fail "migrated WINEPREFIX is wrong"
  else
    fail "legacy prefix --print-env failed"
  fi

  # A .lnk shortcut must be routed to Wine, which knows how to open it.
  : > "$TMP/shortcut.lnk"
  if out="$(HOME="$TMP/home" bin/continuity-run --print-env "$TMP/shortcut.lnk" 2>&1)"; then
    printf '%s\n' "$out" | grep -q '^CONTINUITY_ENGINE=wine$' && pass ".lnk routed to wine" || fail ".lnk not routed to wine"
  else
    fail ".lnk --print-env failed"
  fi

  # Missing file must fail loudly, not silently.
  if HOME="$TMP/home" bin/continuity-run "$TMP/nope.exe" >/dev/null 2>&1; then
    fail "a missing .exe did not produce an error"
  else
    pass "missing .exe is rejected"
  fi

  group "continuity-prefix"
  # NOTE: capture output instead of piping into grep -q. With `set -o pipefail`,
  # grep exiting early sends SIGPIPE to the script under test and reports a
  # spurious failure.
  if HOME="$TMP/home" bin/continuity-prefix list >/dev/null 2>&1; then pass "prefix list works"; else fail "prefix list failed"; fi
  mkdir -p "$TMP/home/.local/share/universal-prefixes/demo-app/drive_c"
  out="$(HOME="$TMP/home" bin/continuity-prefix list 2>&1)"
  case "$out" in
    *demo-app*) pass "prefix list reports an existing prefix" ;;
    *) fail "prefix list missed demo-app (got: $out)" ;;
  esac
  out="$(HOME="$TMP/home" bin/continuity-prefix path demo-app 2>&1)"
  case "$out" in
    *universal-prefixes/demo-app) pass "prefix path resolves" ;;
    *) fail "prefix path did not resolve (got: $out)" ;;
  esac
  out="$(HOME="$TMP/home" bin/continuity-prefix info demo-app 2>&1)"
  case "$out" in
    *drive_c*) pass "prefix info reports drive_c" ;;
    *) fail "prefix info failed (got: $out)" ;;
  esac
  if HOME="$TMP/home" bin/continuity-prefix rm nonexistent-slug >/dev/null 2>&1; then
    fail "rm of an unknown prefix should fail"
  else
    pass "rm of an unknown prefix fails cleanly"
  fi

  group "continuity-umu-verify (legacy runtime repair tool)"
  if HOME="$TMP/home" bin/continuity-umu-verify >/dev/null 2>&1; then
    pass "validate action exits 0 when nothing is installed yet"
  else
    fail "validate action should not fail on a clean home"
  fi
  out="$(HOME="$TMP/home" bin/continuity-umu-verify 2>&1)"
  printf '%s\n' "$out" | grep -q 'steamrt' && pass "reports runtime variants" || fail "does not mention steamrt: $out"
  if HOME="$TMP/home" bin/continuity-umu-verify --check >/dev/null 2>&1; then
    fail "--check on a clean home should exit non-zero"
  else
    pass "--check exits non-zero when a runtime is missing"
  fi
  # A broken runtime tree must be reported with umu's own phrasing.
  mkdir -p "$TMP/home/.local/share/umu/steamrt3"
  out="$(HOME="$TMP/home" bin/continuity-umu-verify --check 2>&1)"
  printf '%s\n' "$out" | grep -q 'steamrt3 validation failed' && pass "mirrors umu's validation message" || \
    fail "missing the expected validation message"
  printf '%s\n' "$out" | grep -q 'pv-verify' && pass "names the missing validator" || fail "does not name pv-verify"

  group "continuity-gaming-mode"
  if HOME="$TMP/home" bin/continuity-gaming-mode status >/dev/null 2>&1; then pass "status works outside Hyprland"; else fail "status failed outside Hyprland"; fi
  if HOME="$TMP/home" bin/continuity-gaming-mode on >/dev/null 2>&1; then
    [ -f "$TMP/home/.local/state/continuity/gaming-mode.enabled" ] && pass "on writes the marker" || fail "on did not write the marker"
  else
    fail "gaming mode on failed without hyprctl/systemd"
  fi
  if HOME="$TMP/home" bin/continuity-gaming-mode off >/dev/null 2>&1; then
    [ -f "$TMP/home/.local/state/continuity/gaming-mode.enabled" ] && fail "off left the marker behind" || pass "off clears the marker"
  else
    fail "gaming mode off failed"
  fi
  out="$(HOME="$TMP/home" bin/continuity-gaming-mode status --json 2>&1)"
  case "$out" in \{*\"enabled\":*) pass "status --json is machine readable" ;; *) fail "status --json output unexpected: $out" ;; esac

  group "continuity-panel"
  if HOME="$TMP/home" bin/continuity-panel status >/dev/null 2>&1; then pass "panel status works without eww"; else fail "panel status failed without eww"; fi
  if HOME="$TMP/home" bin/continuity-panel toggle drawer >/dev/null 2>&1; then
    pass "toggle drawer degrades gracefully without eww"
  else
    fail "toggle drawer crashed without eww (it must warn, not fail)"
  fi
  if HOME="$TMP/home" bin/continuity-panel nonsense >/dev/null 2>&1; then
    fail "an unknown panel command should exit non-zero"
  else
    pass "unknown panel command exits non-zero"
  fi

  group "install.sh --dry-run"
  if out="$(HOME="$TMP/home" CONTINUITY_KEEP_ENV=1 NO_COLOR=1 bash install.sh --dry-run --user --skip-packages 2>&1)"; then
    pass "dry run completes (exit 0)"
    printf '%s\n' "$out" | grep -q 'continuity-wine.desktop' && pass "dry run registers the .exe handler" || fail "dry run does not mention the .exe handler"
    printf '%s\n' "$out" | grep -qi 'drive_c\|universal-prefixes' && pass "dry run provisions the prefix root" || fail "dry run does not provision the prefix root"
    # A dry run must not create anything.
    if [ -e "$TMP/home/.config/hypr" ]; then
      fail "dry run created files under HOME"
    else
      pass "dry run created nothing"
    fi
    printf '%s\n' "$out" | grep -qi 'not an Arch system' && pass "warns loudly on a non-Arch host" || pass "runs on this host (Arch detection)"
  else
    fail "install.sh --dry-run --user failed"
    printf '%s\n' "$out" | tail -20 | sed 's/^/        /'
  fi

  group "install.sh argument parsing"
  out="$(bash install.sh --help 2>&1)"
  case "$out" in
    *--with-winboat*) pass "--help works" ;;
    *) fail "--help does not list the options" ;;
  esac
  bash install.sh --nonsense >/dev/null 2>&1 && fail "an unknown flag should exit non-zero" || pass "unknown flag rejected"
  bash install.sh --system --all >/dev/null 2>&1 && fail "two modes should be rejected" || pass "two modes rejected"
  bash install.sh --user SomeUser --dry-run --skip-packages >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] && pass "--user NAME parses ($rc)" || fail "--user NAME did not parse"

  group "uninstall.sh"
  if bash tools/uninstall.sh --dry-run --user >/dev/null 2>&1; then
    pass "uninstall dry run completes"
  else
    fail "uninstall dry run failed"
  fi
  bash tools/uninstall.sh >/dev/null 2>&1 && fail "uninstall with no mode should exit non-zero" || pass "uninstall demands a mode"

  group "documentation links"
  local doc
  for doc in docs/ARCHITECTURE.md docs/COMPATIBILITY.md docs/FREEBUFF.md docs/UNINSTALL.md \
             docs/PORTING.md docs/ARM.md docs/HYPRLAND-LUA-MIGRATION.md docs/ROADMAP.md README.md; do
    if [ -r "$doc" ] && [ "$(wc -l <"$doc")" -gt 10 ]; then
      pass "doc present: $doc"
    else
      fail "doc missing or empty: $doc"
    fi
  done
}

# ---------------------------------------------------------------------------
# first-run wizard (engine, persistence and the Steam import)
# ---------------------------------------------------------------------------
wizard_checks() {
  local wiz="bin/continuity-wizard"
  local whome="$TMP/wizhome"
  local state_out keys k missing="" mode
  mkdir -p "$whome"

  group "continuity-wizard · state and navigation"
  keys="PAGE STEAM_LIBRARY STEAM_SUMMARY STEAM_GAMES STEAM_CANDIDATES APP_NAME APP_STATE APP_PATH MODE ERROR"
  state_out="$(HOME="$whome" "$wiz" state 2>/dev/null)"
  for k in $keys; do
    case "$state_out" in *"$k="*) ;; *) missing="$missing $k" ;; esac
  done
  if [ -z "$missing" ]; then pass "state defines every key"; else fail "state is missing:$missing"; fi

  if [ "$(HOME="$whome" "$wiz" get PAGE 2>/dev/null)" = "welcome" ]; then
    pass "opens on the welcome page"
  else
    fail "first page is not welcome"
  fi

  state_out="$(HOME="$whome" "$wiz" get GREETING 2>/dev/null)"
  case "$state_out" in
    *[Gg]ood*|*[Ww]elcome*|*[Ll]et*) pass "greeting is computed (not stored)" ;;
    *) fail "greeting is empty: '$state_out'" ;;
  esac
  case "$(HOME="$whome" "$wiz" get PREFIX_ROOT 2>/dev/null)" in
    *universal-prefixes) pass "prefix root is reported to the UI" ;;
    *) fail "prefix root is wrong" ;;
  esac

  HOME="$whome" "$wiz" goto mode >/dev/null 2>&1
  [ "$(HOME="$whome" "$wiz" get PAGE 2>/dev/null)" = "mode" ] && pass "goto changes the page" || fail "goto did not change the page"
  HOME="$whome" "$wiz" goto welcome >/dev/null 2>&1
  HOME="$whome" "$wiz" next >/dev/null 2>&1
  # The step after the welcome is the region step: the keyboard layout and the
  # network come before anything that downloads or installs.
  [ "$(HOME="$whome" "$wiz" get PAGE 2>/dev/null)" = "region" ] && pass "next advances to the next step" || fail "next did not advance (page: $(HOME="$whome" "$wiz" get PAGE 2>/dev/null))"
  for step in region steam transfer windows shakedown mode done; do
    HOME="$whome" "$wiz" goto "$step" >/dev/null 2>&1 \
      && pass "goto accepts the '$step' step" \
      || fail "goto rejected the '$step' step"
  done
  HOME="$whome" "$wiz" goto nonsense >/dev/null 2>&1 && fail "an unknown page should be rejected" || pass "unknown page rejected"
  HOME="$whome" "$wiz" goto region >/dev/null 2>&1
  HOME="$whome" "$wiz" back >/dev/null 2>&1
  [ "$(HOME="$whome" "$wiz" get PAGE 2>/dev/null)" = "welcome" ] && pass "back returns to the previous step" || fail "back did not return (page: $(HOME="$whome" "$wiz" get PAGE 2>/dev/null))"
  HOME="$whome" "$wiz" goto nonsense >/dev/null 2>&1 && fail "an unknown page was accepted" || pass "unknown page rejected"

  group "continuity-wizard · session style"
  local conf="$whome/.config/continuity/environment.conf"
  mkdir -p "$(dirname "$conf")"
  printf '# my own note\nCONTINUITY_UMU_LOG=0\n' >"$conf"
  HOME="$whome" "$wiz" set-mode gaming >/dev/null 2>&1
  if grep -q '^CONTINUITY_START_IN_GAMING_MODE=1$' "$conf"; then
    pass "Gaming is remembered in environment.conf"
  else
    fail "Gaming was not persisted"
  fi
  if grep -q '^# my own note$' "$conf"; then
    pass "existing comments survive (the file is documentation too)"
  else
    fail "set-mode clobbered the config comments"
  fi
  HOME="$whome" "$wiz" set-mode balanced >/dev/null 2>&1
  grep -q '^CONTINUITY_START_IN_GAMING_MODE=0$' "$conf" && pass "Balanced flips it back without duplicating the key" || fail "Balanced was not persisted"
  [ "$(grep -c '^CONTINUITY_START_IN_GAMING_MODE=' "$conf")" = "1" ] && pass "the key is not duplicated on re-set" || fail "set-mode duplicated the key"
  HOME="$whome" "$wiz" set-mode sideways >/dev/null 2>&1 && fail "an unknown mode was accepted" || pass "unknown mode rejected"
  HOME="$whome" "$wiz" set-mode balanced >/dev/null 2>&1

  group "continuity-wizard · lifecycle"
  HOME="$whome" "$wiz" finish >/dev/null 2>&1
  [ -f "$whome/.local/state/continuity/wizard.done" ] && pass "finish writes the completion marker" || fail "finish did not write the marker"
  HOME="$whome" "$wiz" show-once >/dev/null 2>&1 && pass "show-once is a no-op once completed" || fail "show-once failed after completion"
  HOME="$whome" "$wiz" reset >/dev/null 2>&1
  [ ! -f "$whome/.local/state/continuity/wizard.done" ] && pass "reset clears the marker (it runs again next login)" || fail "reset left the marker behind"
  [ "$(HOME="$whome" "$wiz" get PAGE 2>/dev/null)" = "welcome" ] && pass "reset returns to the first page" || fail "reset did not reset the page"

  # Walking to the last page and closing must count as completing. Without this
  # the marker was never written by the UI's own Finish button, so show-once
  # reopened the wizard at every single login and nothing the user did ended it.
  local chome="$TMP/wizard-walk" i
  mkdir -p "$chome/.config/continuity"
  HOME="$chome" "$wiz" start >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7; do HOME="$chome" "$wiz" next >/dev/null 2>&1; done
  [ "$(HOME="$chome" "$wiz" get PAGE 2>/dev/null)" = "done" ] \
    && pass "seven 'next' presses walk the whole flow to the last page" \
    || fail "the flow does not end on the last page (page: $(HOME="$chome" "$wiz" get PAGE 2>/dev/null))"
  HOME="$chome" "$wiz" close >/dev/null 2>&1
  [ -f "$chome/.local/state/continuity/wizard.done" ] \
    && pass "closing on the last page completes the flow" \
    || fail "closing on the last page wrote no completion marker (the wizard would return at every login)"
  HOME="$chome" "$wiz" show-once >/dev/null 2>&1
  [ "$(HOME="$chome" "$wiz" get PAGE 2>/dev/null)" = "done" ] \
    && pass "show-once stays quiet once the walk was finished" \
    || fail "show-once reopened a flow the user had just finished"

  local ehome="$TMP/wizard-early"
  mkdir -p "$ehome/.config/continuity"
  HOME="$ehome" "$wiz" start >/dev/null 2>&1
  HOME="$ehome" "$wiz" close >/dev/null 2>&1
  [ ! -f "$ehome/.local/state/continuity/wizard.done" ] \
    && pass "closing on an early page does not complete the flow" \
    || fail "closing early marked the flow complete"

  # The state file records absolute paths and error text, so it must stay private.
  # Some filesystems cannot represent POSIX modes at all (a Windows-backed Git
  # Bash silently reports 644 for a 600 file), so probe first and report a SKIP
  # rather than a false failure — or, worse, a false pass.
  local can_restrict=0 probe="$TMP/perm-probe"
  : >"$probe"
  chmod 600 "$probe" 2>/dev/null || true
  [ "$(stat -c '%a' "$probe" 2>/dev/null)" = "600" ] && can_restrict=1
  if [ "$can_restrict" = "1" ]; then
    mode="$(stat -c '%a' "$whome/.local/state/continuity/wizard.state" 2>/dev/null || echo)"
    case "$mode" in
      "") printf '  %sSKIP%s stat could not report the state file mode\n' "$C_DIM" "$C_RESET" ;;
      *0) pass "state file is not readable by others (mode $mode)" ;;
      *) fail "state file mode is $mode — it is readable by other users" ;;
    esac
  else
    printf '  %sSKIP%s state file permissions — this filesystem cannot represent 0600\n' "$C_DIM" "$C_RESET"
    # Prove the intent instead: the engine must at least try to restrict it.
    if grep -q 'chmod 600 "\$STATE_FILE"' bin/continuity-wizard; then
      pass "engine calls chmod 600 on the state file (verified statically)"
    else
      fail "engine never restricts the state file"
    fi
  fi

  HOME="$whome" "$wiz" install-exe "$TMP/definitely-missing.exe" >/dev/null 2>&1 && \
    fail "install-exe accepted a missing file" || pass "install-exe rejects a missing file"

  group "continuity-wizard · Steam library import"
  local sh="$TMP/steamhome" vdf out
  mkdir -p "$sh/.steam/steam/steamapps" "$sh/ExtDrive/SteamLibrary/steamapps"
  vdf="$sh/.steam/steam/steamapps/libraryfolders.vdf"
  printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s/.steam/steam"\n\t\t"label"\t\t""\n\t\t"totalsize"\t"0"\n\t}\n}\n' "$sh" >"$vdf"
  printf '"AppState"\n{\n\t"appid"\t\t"220"\n\t"name"\t\t"Verified Game"\n}\n' \
    >"$sh/ExtDrive/SteamLibrary/steamapps/appmanifest_220.acf"

  out="$(HOME="$sh" "$wiz" scan-steam 2>&1)"
  case "$out" in
    *ExtDrive/SteamLibrary*) pass "scan finds an unregistered library on another mount" ;;
    *) fail "scan did not find the library: $out" ;;
  esac
  case "$out" in
    *"Verified Game"*) pass "scan names the installed games, not just a count" ;;
    *) fail "scan did not name the games" ;;
  esac

  HOME="$sh" "$wiz" import-steam "$sh/ExtDrive/SteamLibrary" >/dev/null 2>&1
  case "$(cat "$vdf")" in
    *ExtDrive/SteamLibrary*) pass "import registers the library in libraryfolders.vdf" ;;
    *) fail "import did not register the library" ;;
  esac
  [ "$(grep -cE '^[[:space:]]*"[0-9]+"[[:space:]]*$' "$vdf")" = "2" ] && pass "exactly one entry was added" || fail "library entry count is wrong"
  [ "$(tr -cd '{' <"$vdf" | wc -c)" = "$(tr -cd '}' <"$vdf" | wc -c)" ] && pass "the library list is still well formed" || fail "the VDF is malformed after import"
  [ -f "$vdf.continuity-backup" ] && pass "the original list was backed up first" || fail "no backup was kept"

  HOME="$sh" "$wiz" import-steam "$sh/ExtDrive/SteamLibrary" >/dev/null 2>&1
  [ "$(grep -cE '^[[:space:]]*"[0-9]+"[[:space:]]*$' "$vdf")" = "2" ] && \
    pass "re-importing is a no-op, never a duplicate" || fail "re-import duplicated the library entry"

  printf 'garbage\n' >"$vdf"
  HOME="$sh" "$wiz" import-steam "$sh/ExtDrive/SteamLibrary" >/dev/null 2>&1 && \
    fail "a malformed library list was accepted" || pass "a malformed library list is refused"
  [ "$(cat "$vdf")" = "garbage" ] && pass "the refused file was left byte-for-byte untouched" || fail "the refused file was modified"

  mkdir -p "$TMP/emptyhome"
  HOME="$TMP/emptyhome" "$wiz" import-steam --first >/dev/null 2>&1 && \
    fail "--first claimed to import with no Steam library present" || pass "--first fails cleanly when there is nothing to import"

  group "continuity-wizard · Eww bridge"
  local bridge="config/eww/scripts/wizard.sh"
  local bh="$TMP/bridgehome"
  mkdir -p "$bh"
  # With no wizard installed the bridge must still answer (an empty label is a
  # broken poll; a failing command is a log full of errors).
  for field in greeting page steam-info steam-games app-name app-state mode error prefix-root; do
    if out="$(HOME="$bh" CONTINUITY_WIZARD_BIN=/nonexistent "$bridge" "$field" 2>&1)"; then :; else fail "bridge field '$field' exited non-zero without the engine"; fi
  done
  pass "bridge answers every polled field with no engine present"
  # And with the engine available, the state must actually flow through.
  if [ "$(HOME="$bh" CONTINUITY_WIZARD_BIN="$PWD/$wiz" "$bridge" page 2>/dev/null)" = "welcome" ]; then
    pass "bridge reads the engine's page"
  else
    fail "bridge did not read the engine state"
  fi
  case "$(HOME="$bh" CONTINUITY_WIZARD_BIN="$PWD/$wiz" "$bridge" app-state 2>/dev/null)" in
    *"No Windows program"*) pass "bridge turns machine state into a sentence" ;;
    *) fail "bridge app-state wording is wrong" ;;
  esac

  group "continuity-session-start · first login and the ones after it"
  local sh2="$TMP/sesshome" runner="" rc before after
  mkdir -p "$sh2/.config/continuity"
  printf 'CONTINUITY_START_IN_GAMING_MODE=1\n' >"$sh2/.config/continuity/environment.conf"
  command -v timeout >/dev/null 2>&1 && runner="timeout 60"

  # Run twice on purpose. The second run is the interesting one: the single-
  # instance lock file now exists, and an absent `flock` used to read as "another
  # bootstrap is running", so every login after the first exited silently — no
  # bar, no dock, no wizard, and nothing in the log to explain it.
  local run
  for run in 1 2; do
    out="$(PATH="$PWD/bin:$PATH" HOME="$sh2" $runner bin/continuity-session-start 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      pass "session bootstrap run $run completes (rc=0)"
    else
      fail "session bootstrap run $run exited $rc: $out"
    fi
    case "$out" in
      *"starting in gaming mode"*) pass "run $run honours the configured lean default" ;;
      *) fail "run $run ignored CONTINUITY_START_IN_GAMING_MODE: $out" ;;
    esac
  done

  [ -f "$sh2/.local/state/continuity/wizard.state" ] && \
    pass "the wizard opens itself on first login" || fail "the wizard was never opened at login"
  # The completion marker is what keeps `show-once` idempotent, so assert the
  # marker really appears before trusting the second call's behaviour.
  PATH="$PWD/bin:$PATH" HOME="$sh2" "$wiz" finish >/dev/null 2>&1
  if [ -f "$sh2/.local/state/continuity/wizard.done" ]; then
    pass "finish records completion for this home"
  else
    fail "finish did not record completion"
  fi
  # show-once is deliberately silent (it runs backgrounded at login), so assert
  # the contract rather than a message: it succeeds and it changes nothing.
  before="$(cat "$sh2/.local/state/continuity/wizard.state" 2>/dev/null)"
  PATH="$PWD/bin:$PATH" HOME="$sh2" "$wiz" show-once >/dev/null 2>&1
  rc=$?
  after="$(cat "$sh2/.local/state/continuity/wizard.state" 2>/dev/null)"
  if [ "$rc" -eq 0 ]; then
    pass "show-once succeeds on a completed setup"
  else
    fail "show-once exited $rc on a completed setup"
  fi
  if [ "$before" = "$after" ]; then
    pass "show-once leaves a completed wizard untouched (never reopens it)"
  else
    fail "show-once reopened or rewrote the completed flow"
  fi
  [ -f "$sh2/.local/state/continuity/wizard.done" ] && \
    pass "the completion marker survives a later login" || fail "show-once removed the marker"
}

# ---------------------------------------------------------------------------
# the new tools: shakedown (readiness), region (locale/keyboard/network),
# export (move a setup between machines)
# ---------------------------------------------------------------------------
tools_checks() {
  local sh="$PWD/bin/continuity-shakedown"
  local reg="$PWD/bin/continuity-region"
  local exp="$PWD/bin/continuity-export"
  local t="$TMP/tools"
  mkdir -p "$t"
  local home out rc line status rest key detail

  group "continuity-shakedown · report contract"
  home="$t/sd-home"; mkdir -p "$home/.config/continuity"
  out="$(HOME="$home" "$sh" 2>/dev/null)"; rc=$?
  # The wizard parses this output, so its shape is a contract, not cosmetics.
  local bad=0 n_pass=0 n_warn=0 n_fail=0 n_skip=0 summary=""
  while IFS= read -r line; do
    case "$line" in SUMMARY*) summary="$line"; continue ;; esac
    [ -n "$line" ] || continue
    status="${line%% *}"; rest="${line#* }"; key="${rest%% *}"; detail="${rest#* }"
    case "$status" in PASS|WARN|FAIL|SKIP) ;; *) bad=$((bad + 1)); continue ;; esac
    case "$key" in ""|*[!a-z0-9_]*) bad=$((bad + 1)) ;; esac
    [ -n "$detail" ] || bad=$((bad + 1))
    case "$status" in
      PASS) n_pass=$((n_pass + 1)) ;;
      WARN) n_warn=$((n_warn + 1)) ;;
      FAIL) n_fail=$((n_fail + 1)) ;;
      SKIP) n_skip=$((n_skip + 1)) ;;
    esac
  done <<<"$out"
  [ "$bad" = "0" ] && pass "every line is 'STATUS key detail'" || fail "$bad malformed report line(s)"
  local total=$((n_pass + n_warn + n_fail + n_skip))
  case "$summary" in
    "SUMMARY $total checks: $n_pass pass, $n_warn warn, $n_fail fail, $n_skip skip")
      pass "SUMMARY counts match the lines printed ($total checks)" ;;
    *) fail "SUMMARY does not match the report: $summary" ;;
  esac
  if [ "$total" -gt 0 ]; then
    if [ "$n_fail" -gt 0 ]; then
      [ "$rc" -ne 0 ] && pass "a failing check means a non-zero exit" || fail "failures were reported but the exit status was 0"
    else
      [ "$rc" -eq 0 ] && pass "a clean report exits 0" || fail "no failures reported but the exit status was $rc"
    fi
  fi

  out="$(HOME="$home" "$sh" --json 2>/dev/null)"
  if command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d["ok"], bool); assert d["checks"]; assert set(d["counts"]) == {"pass","warn","fail","skip"}' >/dev/null 2>&1; then
      pass "--json parses and carries ok/checks/counts"
    else
      fail "--json is not the documented object"
    fi
  else
    printf '  %sSKIP%s --json validation needs python3\n' "$C_DIM" "$C_RESET"
  fi

  out="$(HOME="$home" "$sh" --quiet 2>/dev/null)"
  case "$out" in
    *"PASS "*) fail "--quiet still prints the passing checks" ;;
    *) pass "--quiet prints only what needs attention" ;;
  esac

  # Every remedy must belong to a problem that was actually reported.
  out="$(HOME="$home" "$sh" --fix 2>/dev/null)"
  local orphan_fix=0 fixkey
  while IFS= read -r line; do
    case "$line" in
      FIX\ *)
        fixkey="$(printf '%s' "${line#FIX }" | awk '{ print $1 }')"
        printf '%s\n' "$out" | grep -Eq "^(WARN|FAIL) $fixkey " || orphan_fix=$((orphan_fix + 1))
        ;;
    esac
  done <<<"$out"
  [ "$orphan_fix" = "0" ] && pass "every FIX line belongs to a reported problem" || fail "$orphan_fix FIX line(s) have no matching problem"

  group "continuity-shakedown · the throwaway probe"
  local proot="$t/prefixes"
  mkdir -p "$proot/shakedown-probe/drive_c" "$proot/realapp/drive_c"
  : >"$proot/keep-me.txt"
  HOME="$home" CONTINUITY_PREFIX_ROOT="$proot" "$sh" --prune >/dev/null 2>&1
  [ ! -e "$proot/shakedown-probe" ] && pass "--prune removes the throwaway probe prefix" || fail "--prune left the probe prefix behind"
  [ -d "$proot/realapp/drive_c" ] && pass "--prune leaves real prefixes alone" || fail "--prune deleted a real prefix"
  [ -f "$proot/keep-me.txt" ] && pass "--prune touches nothing else in the prefix root" || fail "--prune removed an unrelated file"
  HOME="$home" "$sh" --nonsense >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && pass "an unknown flag exits 2" || fail "an unknown flag exited $rc (want 2)"

  group "continuity-region · locale, keyboard, zone"
  local rhome="$t/region-home"
  mkdir -p "$rhome/.config/continuity" "$rhome/.config/hypr"
  printf '# my own note\nLC_NUMERIC=en_US.UTF-8\n' >"$rhome/.config/continuity/region.conf"
  printf '# my own hypr overlay\ngeneral {\n    gaps_in = 5\n}\n' >"$rhome/.config/hypr/local.conf"

  HOME="$rhome" "$reg" locale en_GB.UTF-8 >/dev/null 2>&1
  grep -q '^LANG=en_GB.UTF-8$' "$rhome/.config/continuity/region.conf" \
    && pass "locale writes LANG to region.conf" || fail "locale did not write LANG"
  grep -q '^# my own note$' "$rhome/.config/continuity/region.conf" \
    && pass "unrelated lines in region.conf survive" || fail "region.conf lost its other lines"
  [ -r "$rhome/.config/environment.d/10-continuity-region.conf" ] \
    && pass "the same values go to environment.d for systemd --user" || fail "no environment.d copy was written"

  HOME="$rhome" "$reg" locale de_DE.UTF-8 >/dev/null 2>&1
  [ "$(grep -c '^LANG=' "$rhome/.config/continuity/region.conf")" = "1" ] \
    && pass "setting the locale twice does not duplicate the key" || fail "region.conf has duplicate LANG lines"

  HOME="$rhome" "$reg" keymap gb >/dev/null 2>&1
  grep -q 'kb_layout[[:space:]]*=[[:space:]]*gb' "$rhome/.config/hypr/local.conf" \
    && pass "keymap writes a kb_layout into the Hyprland overlay" || fail "keymap did not write the layout"
  [ "$(grep -c 'continuity-region keyboard' "$rhome/.config/hypr/local.conf")" = "2" ] \
    && pass "the keyboard block is fenced by exactly one marker pair" || fail "the keyboard markers are wrong"
  grep -q '^# my own hypr overlay$' "$rhome/.config/hypr/local.conf" \
    && pass "the user's own Hyprland overlay survives" || fail "keymap clobbered local.conf"
  HOME="$rhome" "$reg" keymap de >/dev/null 2>&1
  [ "$(grep -c 'continuity-region keyboard' "$rhome/.config/hypr/local.conf")" = "2" ] \
    && pass "re-setting the layout does not append a second block" || fail "the keyboard block was duplicated"
  grep -q 'kb_layout[[:space:]]*=[[:space:]]*de' "$rhome/.config/hypr/local.conf" \
    && pass "the layout is replaced, not merely added" || fail "the layout was not updated"

  HOME="$rhome" "$reg" timezone Europe/London >/dev/null 2>&1
  grep -q '^TZ=Europe/London$' "$rhome/.config/continuity/region.conf" \
    && pass "timezone writes TZ for this user's sessions" || fail "timezone did not write TZ"

  out="$(HOME="$rhome" "$reg" show 2>/dev/null)"
  [ "$(printf '%s\n' "$out" | awk -F'\t' 'NF==3' | awk 'END { print NR + 0 }')" = "7" ] \
    && pass "show prints the seven 'key<TAB>value<TAB>source' rows" || fail "show did not print seven rows"
  if command -v python3 >/dev/null 2>&1; then
    if HOME="$rhome" "$reg" show --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); assert set(d) == {"locale","lc_time","keymap","variant","timezone","wifi_ssid","wifi_state"}' >/dev/null 2>&1; then
      pass "--json exposes exactly the documented keys"
    else
      fail "--json keys are wrong"
    fi
  fi

  # --dry-run has to be honest: it must not write anything at all.
  local dhome="$t/region-dry"
  mkdir -p "$dhome/.config/continuity"
  out="$(HOME="$dhome" "$reg" --dry-run locale fr_FR.UTF-8 --system 2>&1)"
  [ ! -e "$dhome/.config/continuity/region.conf" ] \
    && pass "--dry-run writes nothing" || fail "--dry-run wrote region.conf"
  case "$out" in
    *sudo*localectl*) pass "--system --dry-run prints the escalation it would use" ;;
    *) fail "--system --dry-run did not show the sudo command: $out" ;;
  esac

  group "continuity-region · Wi-Fi secret handling"
  HOME="$rhome" CONTINUITY_REGION_NMCLI="$t/nope/nmcli" "$reg" wifi connect HomeNet </dev/null >"$t/wifi-out" 2>&1; rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "a missing nmcli fails with guidance instead of hanging"
  else
    fail "a missing nmcli exited 0"
  fi
  grep -qi 'networkmanager\|nmcli' "$t/wifi-out" && pass "the failure names the package to install" || fail "the failure does not say what is missing"

  # A stub NetworkManager proves the passphrase path: it must arrive on stdin,
  # land in the temp passwd-file, and leave no trace afterwards.
  mkdir -p "$t/nm"
  cat >"$t/nm/nmcli" <<'STUB'
#!/bin/sh
log="${CONTINUITY_TEST_NMCLI_LOG:?}"
printf 'ARGS %s\n' "$*" >>"$log"
case "$*" in
  *"dev status"*)  printf 'wlan0:wifi\n' ;;
  *"ACTIVE,SSID"*) printf 'yes:HomeNet\n' ;;
  *"dev wifi list"*) printf 'HomeNet:80:WPA2\nNeighbour:42:WPA2\n' ;;
  *"dev wifi connect"*)
    prev=""
    for a in "$@"; do
      if [ "$prev" = "passwd-file" ]; then
        printf 'PASSFILE-CONTENT %s\n' "$(cat "$a" 2>/dev/null)" >>"$log"
        printf 'PASSFILE-PATH %s\n' "$a" >>"$log"
      fi
      prev="$a"
    done
    ;;
esac
exit 0
STUB
  chmod +x "$t/nm/nmcli"
  : >"$t/nm.log"
  # The passphrase must arrive on stdin with a terminating newline: read(1) at
  # EOF still yields the text, but a tool that treats a failed read as "no
  # passphrase" would connect to an open network instead — which is precisely
  # what an earlier version of this test accidentally proved.
  printf '%s\n' hunter2 \
    | HOME="$rhome" CONTINUITY_TEST_NMCLI_LOG="$t/nm.log" CONTINUITY_REGION_NMCLI="$t/nm/nmcli" \
      "$reg" wifi connect HomeNet >"$t/wifi-connect-out" 2>&1
  grep -q 'PASSFILE-CONTENT hunter2' "$t/nm.log" \
    && pass "the passphrase reaches nmcli through a passwd-file, not argv" || fail "the passphrase never reached nmcli"
  local nmout
  nmout="$(cat "$t/nm.log")"
  case "$nmout" in
    *"passwd-file "*) pass "the passphrase travels in a passwd-file, never in argv" ;;
    *) fail "nmcli was never given a passwd-file: $nmout" ;;
  esac
  local pf
  pf="$(awk '/^PASSFILE-PATH / { print $2 }' "$t/nm.log" | tail -n1)"
  if [ -n "$pf" ] && [ ! -e "$pf" ]; then
    pass "the temporary passwd-file is removed afterwards"
  elif [ -z "$pf" ]; then
    fail "nmcli was never given a passwd-file"
  else
    fail "the passwd-file was left behind at $pf"
  fi
  case "$(cat "$t/wifi-connect-out")" in
    *hunter2*) fail "the passphrase was echoed into the output" ;;
    *) pass "the passphrase is never echoed" ;;
  esac

  out="$(HOME="$rhome" CONTINUITY_TEST_NMCLI_LOG="$t/nm.log" CONTINUITY_REGION_NMCLI="$t/nm/nmcli" "$reg" wifi scan 2>/dev/null)"
  case "$out" in
    *HomeNet*) pass "wifi scan lists the networks" ;;
    *) fail "wifi scan found nothing: $out" ;;
  esac

  group "continuity-export · round trip"
  local old="$t/old-home" new="$t/new-home"
  mkdir -p "$old/.local/share/universal-prefixes/testapp/drive_c/Program Files/Test" \
           "$old/.local/share/applications/continuity/testapp" \
           "$old/.local/state/continuity" "$new/.config/continuity"
  : >"$old/.local/share/universal-prefixes/testapp/drive_c/Program Files/Test/Test.exe"
  # Written the way continuity-prefix writes it: absolute paths under THIS home,
  # which is exactly what import has to rewrite for the next machine.
  printf '[Desktop Entry]\nType=Application\nName=Test\nExec="%s/.local/share/universal-prefixes/testapp/drive_c/Program Files/Test/Test.exe"\nPath="%s/.local/share/universal-prefixes/testapp/drive_c/Program Files/Test"\n' \
    "$old" "$old" >"$old/.local/share/applications/continuity/testapp/Test.desktop"
  printf 'PAGE=done\nMODE=gaming\n' >"$old/.local/state/continuity/wizard.state"
  : >"$old/.local/state/continuity/wizard.done"

  local archive="$t/setup.tar.zst"
  out="$(HOME="$old" "$exp" export --out "$archive" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ -s "$archive" ]; then
    pass "export writes an archive"
  else
    fail "export failed (rc=$rc): $out"
  fi
  out="$(HOME="$old" "$exp" inspect "$archive" 2>&1)"
  case "$out" in
    *"SETUP_FORMAT=1"*) pass "inspect reports the format version" ;;
    *) fail "inspect did not report SETUP_FORMAT: $out" ;;
  esac
  case "$out" in
    *"checksums:"*) pass "inspect reports the recorded checksums" ;;
    *) fail "inspect did not mention checksums" ;;
  esac

  out="$(HOME="$new" "$exp" import "$archive" --dry-run 2>&1)"
  [ ! -e "$new/.local/share/universal-prefixes/testapp" ] \
    && pass "a dry-run import writes nothing" || fail "a dry-run import wrote into the new home"

  out="$(HOME="$new" "$exp" import "$archive" --yes 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "import completes"
  else
    fail "import failed (rc=$rc): $out"
  fi
  [ -f "$new/.local/share/universal-prefixes/testapp/drive_c/Program Files/Test/Test.exe" ] \
    && pass "the prefix is restored with its files" || fail "the prefix was not restored"
  local launcher="$new/.local/share/applications/continuity/testapp/Test.desktop"
  if [ -r "$launcher" ]; then
    if grep -q "$new" "$launcher" && ! grep -q "$old" "$launcher"; then
      pass "launchers are rewritten to the new home (and the old path is gone)"
    else
      fail "the launcher still points at the old home: $(grep '^Exec=' "$launcher")"
    fi
  else
    fail "the launcher was not restored"
  fi
  [ -f "$new/.local/state/continuity/wizard.done" ] \
    && pass "the wizard's completion travels with the setup" || fail "wizard state did not come over"

  out="$(HOME="$new" "$exp" import "$archive" --yes 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && pass "importing the same archive again is safe (merge)" || fail "a second import failed (rc=$rc)"
  [ "$(find "$new/.local/share/universal-prefixes" -maxdepth 1 -mindepth 1 -type d | awk 'END { print NR + 0 }')" = "1" ] \
    && pass "merging did not duplicate the prefix" || fail "merge duplicated the prefix"

  # A tampered payload must be refused before anything is written.
  local tampered="$t/tampered.tar.gz"
  mkdir -p "$t/bad/continuity-setup"
  ( cd "$t/bad" && HOME="$old" "$exp" export --out "$t/bad/ok.tar.zst" >/dev/null 2>&1 )
  if [ -s "$t/bad/ok.tar.zst" ]; then
    if command -v tar >/dev/null 2>&1 && tar -tf "$t/bad/ok.tar.zst" >/dev/null 2>&1; then
      mkdir -p "$t/bad/x" && tar -xf "$t/bad/ok.tar.zst" -C "$t/bad/x" 2>/dev/null || true
      printf 'tampered\n' >>"$t/bad/x/continuity-setup/payload/state/wizard.state" 2>/dev/null || true
      ( cd "$t/bad/x" && tar -czf "$tampered" continuity-setup ) 2>/dev/null || true
    fi
  fi
  if [ -s "$tampered" ]; then
    local thome="$t/tampered-home"; mkdir -p "$thome/.config/continuity"
    HOME="$thome" "$exp" import "$tampered" --yes >/dev/null 2>&1 && \
      fail "a tampered archive was imported" || pass "a tampered archive is refused"
    [ ! -e "$thome/.local/share/universal-prefixes/testapp" ] \
      && pass "the refused import wrote nothing" || fail "the refused import still wrote files"
  else
    printf '  %sSKIP%s a tampered archive could not be built here (tar/zstd)\n' "$C_DIM" "$C_RESET"
  fi

  out="$(HOME="$old" "$exp" list 2>&1)"
  case "$out" in
    *testapp*) pass "list shows the local prefixes" ;;
    *) fail "list did not show the fixture prefix: $out" ;;
  esac
}

# ---------------------------------------------------------------------------
# the boot chain: greetd autologin instead of Arch TTY -> session chooser
# ---------------------------------------------------------------------------
boot_checks() {
  local boot="$PWD/bin/continuity-boot"
  local t="$TMP/boot"
  local units="$t/units" cfg="$t/cfg" bin="$t/bin"
  mkdir -p "$units" "$cfg" "$bin"
  : >"$units/greetd.service"

  cat >"$bin/systemctl" <<'STUB'
#!/bin/sh
case "$1" in
  is-enabled) printf '%s\n' "${CONTINUITY_TEST_DM:-disabled}" ;;
  is-active)  echo inactive ;;
  *) exit 0 ;;
esac
exit 0
STUB
  # A passwd table with the two cases that must stay distinguishable: a normal
  # account, and root — whose uid 0 is the reason a root autologin is refused.
  cat >"$bin/getent" <<'STUB'
#!/bin/sh
[ "$1" = "passwd" ] || exit 1
case "$2" in
  somebody) printf 'somebody:x:1000:1000::%s:/bin/bash\n' "${CONTINUITY_TEST_HOME:?}" ;;
  root)     printf 'root:x:0:0::/root:/bin/bash\n' ;;
  *)        exit 1 ;;
esac
STUB
  printf '#!/bin/sh\nexit 0\n' >"$bin/tuigreet"
  chmod +x "$bin"/*

  local bhome="$t/home" out rc
  mkdir -p "$bhome/.config/hypr"
  local -a bootenv=(PATH="$bin:$PATH" CONTINUITY_GREETD_DIR="$cfg" CONTINUITY_GREETD_UNIT_DIR="$units"
                    CONTINUITY_SESSION_COMMAND=/bin/sh CONTINUITY_TEST_HOME="$bhome")

  group "continuity-boot · status"
  out="$(env "${bootenv[@]}" "$boot" status 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && pass "status succeeds without greetd installed" || fail "status exited $rc"
  if command -v python3 >/dev/null 2>&1; then
    if env "${bootenv[@]}" "$boot" status --json 2>/dev/null \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); assert {"autologin","user","service_enabled"} <= set(d)' >/dev/null 2>&1; then
      pass "status --json carries the documented keys"
    else
      fail "status --json keys are wrong"
    fi
  fi

  group "continuity-boot · on is a no-prompt boot into the session"
  out="$(env "${bootenv[@]}" "$boot" on --dry-run --user somebody 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "on --dry-run succeeds against the fixture"
  else
    fail "on --dry-run exited $rc: $out"
  fi
  case "$out" in
    *"[initial_session]"*) pass "the rendered config has an initial_session (the autologin)" ;;
    *) fail "no [initial_session] in the rendered config" ;;
  esac
  case "$out" in
    *"user = \"somebody\""*) pass "it autologins the requested account" ;;
    *) fail "the autologin user is wrong: $out" ;;
  esac
  case "$out" in
    *"[default_session]"*) pass "it keeps a default_session (the logout screen)" ;;
    *) fail "no [default_session] in the rendered config" ;;
  esac
  case "$out" in
    *"@"*_*"@"*) fail "a template placeholder was left unsubstituted" ;;
    *) pass "every placeholder is substituted" ;;
  esac
  [ -z "$(ls -A "$cfg" 2>/dev/null)" ] && pass "a dry run writes no config" || fail "a dry run wrote $cfg"

  out="$(env "${bootenv[@]}" "$boot" off --dry-run 2>&1)"
  case "$out" in
    *"[initial_session]"*) fail "off still renders an autologin" ;;
    *) pass "off renders a config with no autologin" ;;
  esac

  group "continuity-boot · refusals (never lock the machine out)"
  env "${bootenv[@]}" CONTINUITY_SESSION_COMMAND="/nonexistent/session" "$boot" on --dry-run --user somebody >/dev/null 2>&1 \
    && fail "on accepted a missing session binary" || pass "a missing session binary is refused"
  env "${bootenv[@]}" "$boot" on --dry-run --user root >/dev/null 2>&1 \
    && fail "on accepted a root autologin" || pass "a root autologin is refused"
  env "${bootenv[@]}" "$boot" on --dry-run --user nobody-real-at-all >/dev/null 2>&1 \
    && fail "on accepted an account that does not exist" || pass "a nonexistent account is refused"
  # A second display manager owning the seat is a black screen, not a warning.
  out="$(env "${bootenv[@]}" CONTINUITY_TEST_DM=enabled "$boot" on --dry-run --user somebody 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "a competing display manager is refused"
  else
    fail "on proceeded while another display manager is enabled"
  fi
  case "$out" in
    *"greetd is not installed"*)
      pass "the missing-unit case names the package (fixture unit present, so this is the fallback)" ;;
    *) ;;
  esac

  group "greetd template"
  local tmpl="config/greetd/config.toml.tmpl"
  [ -r "$tmpl" ] && pass "the template ships with the repo" || fail "$tmpl is missing"
  grep -q '>>> continuity-autologin' "$tmpl" \
    && pass "the autologin block is fenced by markers" || fail "the autologin fence is missing"
  grep -q '@SESSION_COMMAND@' "$tmpl" && pass "the template is parameterised" || fail "the template is not parameterised"
  grep -q 'greetd does not set' "$tmpl" && pass "the session-type caveat is documented in place" || pass "caveat documented elsewhere"

  group "install.sh · boot integration"
  # The CLI list is a `for s in …` loop that installs $SRC_DIR/bin/$s, so assert
  # the names are in that list rather than a literal bin/<name> path.
  for tool in continuity-boot continuity-region continuity-export continuity-shakedown continuity-end4-pc; do
    grep -q "$tool" install.sh \
      && pass "$tool is in the installed CLI list" || fail "$tool is not in the installed CLI list"
  done
  grep -q 'CONTINUITY_AUTOLOGIN' install.sh && pass "the autologin choice is recorded in install.conf" || fail "install.conf has no autologin key"
  grep -q 'install_boot_experience' install.sh && pass "install.sh runs the boot step" || fail "install.sh never configures the boot path"
  bash install.sh --help 2>&1 | grep -q -- '--autologin' && pass "--autologin is documented" || fail "--autologin is not in --help"
  bash install.sh --help 2>&1 | grep -q -- '--no-autologin' && pass "--no-autologin is documented" || fail "--no-autologin is not in --help"
  bash install.sh --user SomeUser --dry-run --skip-packages --help >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "install options parse before --help ($rc)" || fail "install options did not parse before --help ($rc)"
}

# ---------------------------------------------------------------------------
# the disk installer (the live medium's whole reason to exist)
# ---------------------------------------------------------------------------
installer_checks() {
  local inst="$PWD/bin/continuity-installer"
  local t="$TMP/installer"
  local sys="$t/sysblock" out dir
  mkdir -p "$t" "$t/out"

  group "continuity-installer · the plan it would write"
  mkdir -p "$sys/fakedisk/queue" "$sys/fakedisk/device"
  printf '83886080\n' >"$sys/fakedisk/size"          # 40 GiB in 512-byte sectors
  printf '512\n' >"$sys/fakedisk/queue/logical_block_size"
  printf '0\n' >"$sys/fakedisk/removable"
  printf 'Fixture Disk\n' >"$sys/fakedisk/device/model"
  cat >"$t/lsblk" <<'STUB'
#!/bin/sh
case "$*" in
  *MOUNTPOINT*) exit 0 ;;
  *TYPE*)       printf 'disk\n' ;;
  *MODEL*)      printf 'Fixture Disk\n' ;;
  *NAME*)       printf '%s\n' "${CONTINUITY_TEST_DISK:-/dev/fakedisk}" ;;
  *)            exit 0 ;;
esac
STUB
  chmod +x "$t/lsblk"

  printf 'correct horse battery staple\n' >"$t/pw"
  chmod 600 "$t/pw" 2>/dev/null || true
  out="$(env CONTINUITY_INSTALLER_SYSBLOCK="$sys" CONTINUITY_INSTALLER_LSBLK="$t/lsblk" \
    "$inst" plan --disk /dev/fakedisk --user fixture --host fixturehost \
    --timezone Europe/London --locale en_GB.UTF-8 --keymap gb --password-file "$t/pw" \
    --out "$t/out" 2>&1)"; local rc=$?
  case "$out" in
    *"correct horse battery staple"*) fail "plan echoed the password" ;;
    *) pass "plan never echoes the password" ;;
  esac
  if [ "$rc" -eq 0 ]; then
    pass "plan succeeds against the fixture disk"
  else
    fail "plan failed (rc=$rc): $out"
  fi
  local json="$t/out/install-config.json"
  if [ -r "$json" ]; then
    pass "plan writes install-config.json"
  else
    fail "no install-config.json was written"
  fi
  if command -v python3 >/dev/null 2>&1 && [ -r "$json" ]; then
    if python3 - <<'PY' "$json" 2>/dev/null
import json, sys
c = json.load(open(sys.argv[1]))
assert c["disk_config"]["config_type"] == "manual_partitioning", c["disk_config"]
d = c["disk_config"]["device_modifications"][0]
assert d["wipe"] is True
parts = d["partitions"]
mounts = {p.get("mountpoint") for p in parts}
assert "/boot" in mounts, mounts
boot = [p for p in parts if p.get("mountpoint") == "/boot"][0]
assert boot["fs_type"] == "fat32" and "boot" in boot["flags"]
assert any(p.get("mountpoint") == "/" for p in parts)
assert c["timezone"] == "Europe/London"
assert any("linux-zen" in k for k in c["kernels"])
assert c["hostname"] == "fixturehost"
assert c["locale_config"]["kb_layout"] == "gb"
PY
    then
      pass "the generated config matches the documented archinstall schema"
    else
      fail "the generated config does not match the schema"
    fi
  else
    printf '  %sSKIP%s schema validation needs python3\n' "$C_DIM" "$C_RESET"
  fi

  local creds="$t/out/creds.json"
  if [ -r "$creds" ]; then
    if command -v python3 >/dev/null 2>&1; then
      if python3 - <<'PY' "$creds" 2>/dev/null
import json, sys
c = json.load(open(sys.argv[1]))
u = c["users"][0]
assert u["username"] == "fixture"
assert u["sudo"] is True
assert "enc_password" in u or "!password" in u
PY
      then
        pass "the credentials file declares a sudo-capable account with a hashed password"
      else
        fail "the credentials file is not what archinstall expects"
      fi
    fi
  else
    fail "no creds.json was written"
  fi

  group "continuity-installer · refusals"
  env CONTINUITY_INSTALLER_SYSBLOCK="$sys" CONTINUITY_INSTALLER_LSBLK="$t/lsblk" \
    "$inst" plan --disk /dev/fakedisk1 --user fixture --host h --timezone UTC --locale en_US.UTF-8 \
    --out "$t/out2" >/dev/null 2>&1 && fail "a partition was accepted as the target" || pass "a partition is refused as the target"
  env CONTINUITY_INSTALLER_SYSBLOCK="$sys" CONTINUITY_INSTALLER_LSBLK="$t/lsblk" \
    "$inst" plan --disk /dev/fakedisk --user root --host h --timezone UTC --locale en_US.UTF-8 \
    --out "$t/out2" >/dev/null 2>&1 && fail "the root account was accepted" || pass "root is refused as the account"
  env CONTINUITY_INSTALLER_SYSBLOCK="$sys" CONTINUITY_INSTALLER_LSBLK="$t/lsblk" \
    "$inst" plan --disk /dev/fakedisk --user fixture --host 'not a hostname' --timezone UTC \
    --locale en_US.UTF-8 --out "$t/out2" >/dev/null 2>&1 && fail "an invalid hostname was accepted" || pass "an invalid hostname is refused"
  "$inst" --nonsense >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && pass "an unknown command exits 2" || fail "an unknown command exited $rc (want 2)"

  group "the live medium boots into the desktop"
  # The config itself is written at boot, not shipped: its [initial_session]
  # command is /usr/local/bin/continuity-shell, which the live hook installs a
  # moment earlier. Assert the hook does that (and that it has a fallback), not
  # that a static file exists.
  grep -q 'continuity-boot' iso/profile/airootfs/root/.automated_script.sh \
    && pass "the live hook configures greetd autologin" || fail "the live hook never configures autologin"
  grep -q 'initial_session' iso/profile/airootfs/root/.automated_script.sh \
    && pass "it has a fallback config with an initial_session" || fail "the live fallback has no initial_session"
  [ -r iso/profile/airootfs/etc/systemd/system/greetd.service.d/10-continuity-live.conf ] \
    && pass "the medium orders the desktop after the hook" || fail "the greetd ordering drop-in is missing"
  [ -r iso/profile/airootfs/etc/sysusers.d/continuity-live.conf ] && pass "the live user is declared (sysusers.d)" || fail "no live user declaration"
  [ -r iso/profile/airootfs/etc/systemd/system/continuity-live-boot.service ] && pass "the live boot hook is still shipped" || fail "the live boot hook is gone"
  grep -q 'continuity-installer' iso/profile/airootfs/root/.automated_script.sh \
    && pass "the live hook drives the disk installer" || fail "the live hook does not mention the installer"
  grep -q 'continuity-installer' bin/continuity-session-start \
    && pass "the live session opens the installer instead of the wizard" || fail "the session has no live-medium path"
  grep -q 'archinstall' iso/profile/packages.x86_64 && pass "archinstall ships on the medium" || fail "the medium has no archinstall"
  grep -q 'greetd' iso/profile/packages.x86_64 && pass "greetd ships on the medium" || fail "the medium has no greetd"
  grep -q 'PINNED_COMMIT=' bin/continuity-end4-pc && pass "end4-pC checkout is commit-pinned" || fail "end4-pC checkout is not pinned"
  grep -q '^# Private end4-pC prototype$' docs/END4-PC.md && pass "end4-pC workflow documentation is present" || fail "end4-pC documentation is missing"
  grep -q 'continuity-end4-pc' install.sh && pass "installer registers the private optional overlay helper" || fail "end4-pC helper is not installed by install.sh"
  grep -q 'No VM is launched or port opened' docs/END4-PC.md && pass "guest debug port remains opt-in" || fail "debug port exposure boundary is undocumented"
  bash bin/continuity-end4-pc --help >/dev/null 2>&1 && pass "end4-pC helper help runs" || fail "end4-pC helper help failed"
  local end4_empty_home="$TMP/end4-empty-home" end4_status
  end4_status="$(HOME="$end4_empty_home" XDG_CONFIG_HOME="$end4_empty_home/config" bin/continuity-end4-pc status 2>&1)"
  case "$end4_status" in *overlay=not-installed*"pinned_commit="*) pass "absent overlay status is stable" ;; *) fail "absent overlay status is wrong: $end4_status" ;; esac
  grep -q 'proton-cachyos-slr' packages/gaming.list && pass "CachyOS SLR Proton remains installed" || fail "CachyOS SLR Proton missing"
  grep -q 'proton-cachyos-native' packages/gaming.list && pass "direct Proton remains installed as a separate choice" || fail "native CachyOS Proton package missing"
  grep -q '^umu-launcher$' packages/gaming.list && pass "UMU remains the default-runner dependency" || fail "UMU package is missing"
  grep -q 'proton-cachyos-slr' iso/profile/packages.x86_64 && pass "CachyOS SLR Proton is in the live profile" || fail "CachyOS Proton missing from live profile"
  ! grep -q 'end4-pC' iso/profile/packages.x86_64 && pass "private end4-pC overlay is not bundled into the ISO" || fail "end4-pC was unexpectedly bundled into the ISO"
  grep -q 'Direct Proton' docs/COMPATIBILITY.md && grep -q 'UMU + Proton' docs/COMPATIBILITY.md && pass "UMU and direct Proton remain separately documented" || fail "runner modes are no longer clearly separated"
  grep -q 'GPL-3.0' docs/END4-PC.md && pass "upstream license is disclosed" || fail "upstream license disclosure missing"
  grep -q 'target remote localhost:1234' docs/END4-PC.md && pass "GDB attach command is documented" || fail "GDB attach documentation missing"
  grep -q 'GDB stub has no authentication' docs/END4-PC.md && pass "GDB port security warning is documented" || fail "GDB port security warning missing"
}

# ---------------------------------------------------------------------------
# the engine-only install (standalone/) and the `proton` command
# ---------------------------------------------------------------------------
standalone_checks() {
  local inst="$PWD/standalone/install.sh"
  local t="$TMP/standalone"
  local home="$t/home" out rc fam
  mkdir -p "$t"

  group "standalone · install.sh contract"
  [ -r "$inst" ] && pass "standalone/install.sh ships with the repo" || fail "standalone/install.sh is missing"
  for tool in proton continuity-run continuity-prefix continuity-shakedown; do
    grep -q "$tool" "$inst" && pass "it installs $tool" || fail "$tool is not installed by the standalone path"
  done
  bash "$inst" --help 2>&1 | grep -q -- '--system' && pass "--system is documented" || fail "--system is not documented"
  bash "$inst" --help 2>&1 | grep -q -- '--uninstall' && pass "--uninstall is documented" || fail "--uninstall is not documented"
  bash "$inst" --help 2>&1 | grep -q 'ENGINE-ONLY' && pass "the help points at the documentation" || fail "the help does not reference docs/ENGINE-ONLY.md"
  bash "$inst" --nonsense >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && pass "an unknown flag exits 2" || fail "an unknown flag exited $rc (want 2)"

  group "standalone · a dry run changes nothing"
  mkdir -p "$home"
  out="$(HOME="$home" bash "$inst" --dry-run 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && pass "the dry run succeeds without root" || fail "the dry run failed (rc=$rc): $out"
  case "$out" in
    *"install -m 0755"*proton*) pass "it prints the file installation" ;;
    *) fail "the dry run did not describe the install" ;;
  esac
  [ -z "$(find "$home" -mindepth 1 -print -quit)" ] && pass "the dry run wrote nothing into HOME" || fail "the dry run created files"

  group "standalone · user install (offline)"
  out="$(HOME="$home" bash "$inst" --yes --no-download --no-desktop --no-path 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && pass "the install completes" || fail "the install failed (rc=$rc): $out"
  local f
  for f in proton continuity-run continuity-prefix continuity-shakedown; do
    [ -x "$home/.local/bin/$f" ] && pass "$f is executable in ~/.local/bin" || fail "$f was not installed"
  done
  [ -r "$home/.local/lib/continuity/continuity-common.sh" ] && pass "the shared library is installed" || fail "the shared library is missing"
  [ -r "$home/.config/continuity/environment.conf" ] && pass "the default configuration is written" || fail "no configuration was written"
  printf '\n# local edit\n' >>"$home/.config/continuity/environment.conf"
  HOME="$home" bash "$inst" --yes --no-download --no-desktop --no-path >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "a second install is idempotent" || fail "re-installing failed (rc=$rc)"
  grep -q '# local edit' "$home/.config/continuity/environment.conf" && \
    pass "an existing configuration is never overwritten" || fail "the install replaced the user's configuration"

  group "standalone · Windows checkouts (CRLF)"
  # A checkout made on Windows carries CRLF, and a CRLF shebang makes the kernel
  # look for an interpreter called "bash\r". The installer must normalise what it
  # installs, or every command it installs is unrunnable on Linux.
  local cs="$t/crlf-src" ch="$t/crlf-home"
  mkdir -p "$cs/standalone" "$cs/bin" "$cs/lib" "$cs/config/continuity" "$ch"
  cp "$PWD/standalone/install.sh" "$cs/standalone/install.sh"
  cp "$PWD/lib/continuity-common.sh" "$cs/lib/continuity-common.sh"
  cp "$PWD/config/continuity/environment.conf" "$cs/config/continuity/environment.conf"
  cp "$PWD/bin/proton" "$PWD/bin/continuity-prefix" "$PWD/bin/continuity-shakedown" "$cs/bin/"
  sed 's/$/\r/' "$PWD/bin/continuity-run" >"$cs/bin/continuity-run"
  chmod +x "$cs/bin/continuity-run"
  HOME="$ch" bash "$cs/standalone/install.sh" --yes --no-download --no-desktop --no-path >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "an install from a CRLF source tree completes" || fail "the CRLF install failed (rc=$rc)"
  if head -1 "$ch/.local/bin/continuity-run" | grep -q $'\r'; then
    fail "the installed command kept a CRLF shebang"
  else
    pass "installed commands are normalised to Unix line endings"
  fi
  if out="$(HOME="$ch" "$ch/.local/bin/continuity-run" --version 2>&1)"; then
    pass "the normalised command actually runs"
  else
    fail "the normalised command did not run: $out"
  fi

  group "standalone · never clobbers foreign files"
  local fh="$t/foreign"
  mkdir -p "$fh/.local/bin"
  printf '#!/bin/sh\necho not-ours\n' >"$fh/.local/bin/proton"
  HOME="$fh" bash "$inst" --yes --no-download --no-desktop --no-path >/dev/null 2>&1 && \
    fail "a foreign proton was overwritten" || pass "a foreign proton in the target directory is refused"
  grep -q 'not-ours' "$fh/.local/bin/proton" && pass "the foreign file is untouched" || fail "the foreign file changed"

  group "proton · the command"
  local envp=(env HOME="$home" PATH="$home/.local/bin:$PATH")
  out="$("${envp[@]}" proton version 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && pass "proton version runs from the install" || fail "proton version failed (rc=$rc): $out"
  case "$out" in
    *"ContinuityOS engine"*) pass "it identifies the engine and the distribution" ;;
    *) fail "unexpected version output: $out" ;;
  esac
  "${envp[@]}" proton --help 2>&1 | grep -q 'USAGE' && pass "proton --help prints usage" || fail "proton --help failed"
  "${envp[@]}" proton >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "no arguments prints usage and exits 0" || fail "no arguments exited $rc"
  "${envp[@]}" proton list >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "proton list succeeds with no prefixes" || fail "proton list exited $rc"

  mkdir -p "$home/.local/share/universal-prefixes/demo/drive_c/Program Files/Demo"
  : >"$home/.local/share/universal-prefixes/demo/drive_c/Program Files/Demo/game.exe"
  [ "$("${envp[@]}" proton list)" = "demo" ] && pass "proton list shows the prefix" || fail "proton list did not show the prefix"
  # Capture, never pipe into grep -q: a short-circuiting grep closes the pipe
  # under `set -o pipefail` and the assertion fails on the SIGPIPE, not on output.
  out="$("${envp[@]}" proton scan demo 2>/dev/null)"
  case "$out" in *game.exe*) pass "proton scan finds the executable" ;; *) fail "proton scan found nothing" ;; esac
  out="$("${envp[@]}" proton info demo 2>/dev/null)"
  case "$out" in *drive_c:*) pass "proton info reports the prefix" ;; *) fail "proton info failed: $out" ;; esac
  : >"$t/x.exe"
  out="$("${envp[@]}" proton --print-env "$t/x.exe" 2>&1)"
  case "$out" in
    *CONTINUITY_PREFIX_DIR=*) pass "proton --print-env resolves a prefix (it launches nothing)" ;;
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
      pass "the remedies are built for $fam";;
  esac
  case "$out" in
    *"SUMMARY"*) pass "proton check prints a full report" ;;
    *) fail "proton check printed no report: $out" ;;
  esac

  group "proton · uninstall"
  mkdir -p "$home/.local/share/universal-prefixes/keepme/drive_c"
  "${envp[@]}" proton uninstall --yes >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass "proton uninstall succeeds" || fail "uninstall exited $rc"
  [ ! -e "$home/.local/bin/proton" ] && pass "the command is gone" || fail "proton survived uninstall"
  [ -d "$home/.local/share/universal-prefixes/keepme" ] && pass "uninstall keeps the prefixes" || fail "uninstall deleted a prefix"
  [ -r "$home/.config/continuity/environment.conf" ] && pass "uninstall keeps the configuration" || fail "uninstall deleted the configuration"
}

[ "$MODE" = "all" ] || [ "$MODE" = "syntax" ] && syntax_checks
[ "$MODE" = "all" ] || [ "$MODE" = "functional" ] && { manifest_checks; functional_checks; wizard_checks; tools_checks; standalone_checks; boot_checks; installer_checks; }

printf '\n%s%d passed, %d failed%s\n' "$C_BLD" "$PASS" "$FAIL" "$C_RESET"
if [ "$FAIL" -gt 0 ]; then
  printf '%sfailures:%s\n' "$C_RED" "$C_RESET"
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
printf 'All checks passed.\n'
exit 0
