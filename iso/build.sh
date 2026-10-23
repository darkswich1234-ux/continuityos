#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ContinuityOS — ISO builder
#
#   ./iso/build.sh                  build with defaults
#   ./iso/build.sh --work DIR --out DIR
#   CONTINUITY_ISO_BUILD_DIR=/mnt/big/continuity ./iso/build.sh
#
# What it does, in order:
#   1. Sanity-checks the host (mkarchiso present, enough free space, repo layout).
#   2. Copies iso/profile/ into a scratch directory (never edits the checkout).
#   3. Embeds this repository into airootfs/opt/continuityos, which is what the
#      live medium's unattended install runs.
#   4. Enables the live units by creating the systemd wants-symlinks inside the
#      scratch airootfs (symlinks cannot be represented in the plain-file repo,
#      and archiso has no "enable this unit" declaration). That is what makes the
#      medium boot into the ContinuityOS desktop: NetworkManager.service (the
#      install transaction needs a network) and greetd.service (whose
#      [initial_session], written by the boot hook, runs the session with no
#      greeter), plus the boot hook itself.
#   5. Runs mkarchiso and prints the resulting ISO + SHA256SUMS.
#
# Nothing outside $BUILD_DIR is ever modified or deleted.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE_SRC="$REPO_ROOT/iso/profile"
BUILD_DIR="${CONTINUITY_ISO_BUILD_DIR:-$REPO_ROOT/build}"
WORK_DIR="$BUILD_DIR/work"
OUT_DIR="$BUILD_DIR/out"
PROFILE_DIR="$WORK_DIR/profile"
MKARCHISO_WORK="$WORK_DIR/mkarchiso"
ISO_PAYLOAD_DIR="opt/continuityos"

usage() {
  cat <<EOF
ContinuityOS ISO builder

USAGE
  $(basename "$0") [--work DIR] [--out DIR] [--keep] [--skip-checks]

OPTIONS
  --work DIR       scratch directory for the profile copy + mkarchiso work
                   (default: $WORK_DIR)
  --out DIR        where the .iso and SHA256SUMS land (default: $OUT_DIR)
  --keep           keep the scratch tree on success (it is kept on failure anyway)
  --skip-checks    skip the free-space pre-flight check (UEFI contract checks remain enabled)
  -h, --help       this help

ENVIRONMENT
  CONTINUITY_ISO_BUILD_DIR   base for both work and out directories
  CONTINUITY_ISO_MKARCHISO   override the mkarchiso command (default: mkarchiso)

NOTES
  * mkarchiso must run as root. This script re-executes itself through sudo when
    it is not already root.
  * Build needs roughly 12 GiB free for the work tree plus ~3 GiB for the ISO.
  * The ISO is unsigned. See iso/README.md for what that does and does not mean.
EOF
}

# Resolve a user-supplied directory to an absolute path, creating it if needed
# so a relative path does not silently become "/": we cd into the parent.
abspath() {
  local target="$1" parent base
  base="$(basename -- "$target")"
  parent="$(dirname -- "$target")"
  mkdir -p -- "$parent" 2>/dev/null || { echo "$target"; return 0; }
  parent="$(cd -- "$parent" && pwd)"
  printf '%s/%s' "$parent" "$base"
}

KEEP=0
SKIP_CHECKS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --work) [ $# -ge 2 ] || { echo "--work needs a directory" >&2; exit 2; }
            WORK_DIR="$(abspath "$2")"; shift 2 ;;
    --out)  [ $# -ge 2 ] || { echo "--out needs a directory" >&2; exit 2; }
            OUT_DIR="$(abspath "$2")"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done

PROFILE_DIR="$WORK_DIR/profile"
MKARCHISO_WORK="$WORK_DIR/mkarchiso"

log()  { printf '[iso] %s\n' "$*"; }
warn() { printf '[iso] warning: %s\n' "$*" >&2; }
die()  { printf '[iso] error: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found${2:+ — $2}"
}

# --- 1. pre-flight -----------------------------------------------------------
need rsync "sudo pacman -S rsync"
need find
need awk
need xorriso "sudo pacman -S libisoburn (required to validate UEFI boot metadata)"

MKARCHISO_CMD="${CONTINUITY_ISO_MKARCHISO:-mkarchiso}"
if ! command -v "$MKARCHISO_CMD" >/dev/null 2>&1; then
  die "mkarchiso not found — install the 'archiso' package (sudo pacman -S archiso)"
fi

[ -f "$PROFILE_SRC/profiledef.sh" ] || die "profile not found at $PROFILE_SRC/profiledef.sh"
[ -f "$PROFILE_SRC/packages.x86_64" ] || die "missing $PROFILE_SRC/packages.x86_64"
[ -f "$REPO_ROOT/install.sh" ] || die "missing $REPO_ROOT/install.sh — the ISO payload embeds the repo"

# Never let a mistyped --work delete something real.
case "$WORK_DIR" in
  ""|/|/home|/root|/usr|/etc|"$REPO_ROOT"|"$REPO_ROOT"/*/..) die "refusing to use '$WORK_DIR' as a work directory" ;;
esac

for required in \
  "$PROFILE_SRC/profiledef.sh" \
  "$PROFILE_SRC/pacman.conf" \
  "$PROFILE_SRC/efiboot/loader/loader.conf" \
  "$PROFILE_SRC/efiboot/loader/entries/01-continuityos.conf" \
  "$PROFILE_SRC/airootfs/root/.automated_script.sh" \
  "$PROFILE_SRC/airootfs/etc/sysusers.d/continuity-live.conf" \
  "$PROFILE_SRC/airootfs/etc/sudoers.d/continuity-live" \
  "$PROFILE_SRC/airootfs/etc/systemd/system/greetd.service.d/10-continuity-live.conf" ; do
  [ -e "$required" ] || die "profile is incomplete: $required is missing"
done

# UEFI-only profile contract: don't accidentally reintroduce BIOS/syslinux
# boot files, and keep the systemd-boot entry aligned with the shipped kernel.
[ ! -e "$PROFILE_SRC/syslinux" ] || die "legacy syslinux profile found; this ISO is UEFI-only"
[ "$(grep -c '^bootmodes=' "$PROFILE_SRC/profiledef.sh")" -eq 1 ] || die "expected one bootmodes declaration"
grep -Fq "bootmodes=('uefi.systemd-boot')" "$PROFILE_SRC/profiledef.sh" || \
  die "bootmodes must be UEFI-only: bootmodes=('uefi.systemd-boot')"
if ! grep -q 'linux-zen' "$PROFILE_SRC/packages.x86_64"; then
  die "packages.x86_64 must include linux-zen for the UEFI entry"
fi
if ! grep -q 'vmlinuz-linux-zen' "$PROFILE_SRC/efiboot/loader/entries/01-continuityos.conf"; then
  die "UEFI systemd-boot entry does not reference vmlinuz-linux-zen"
fi
if ! grep -q 'initramfs-linux-zen.img' "$PROFILE_SRC/efiboot/loader/entries/01-continuityos.conf"; then
  die "UEFI systemd-boot entry does not reference initramfs-linux-zen.img"
fi

# Check the UEFI-only boot mode against the installed archiso releng profile.
# Upstream mode names have changed over time; reject a mode unsupported by the
# locally installed archiso before launching a long build.
if [ "$SKIP_CHECKS" != "1" ]; then
  releng="/usr/share/archiso/configs/releng/profiledef.sh"
  if [ -r "$releng" ]; then
    if ! grep -Fq "'uefi.systemd-boot'" "$releng"; then
      if grep -Fq "'uefi.systemd-boot.esp'" "$releng" && grep -Fq "'uefi.systemd-boot.eltorito'" "$releng"; then
        die "installed archiso uses the legacy split UEFI mode; update bootmodes to its UEFI-only spelling before building"
      fi
      die "this archiso does not support bootmodes=('uefi.systemd-boot'); use its UEFI-only spelling"
    fi
    log "UEFI-only boot mode matches the installed archiso releng profile"
  else
    warn "could not read $releng to verify UEFI boot-mode spelling"
  fi

  # Free space: mkarchiso writes a full pacman cache and a squashfs.
  mkdir -p "$BUILD_DIR" 2>/dev/null || die "cannot create $BUILD_DIR"
  avail_kb="$(df -Pk "$BUILD_DIR" | awk 'NR==2 {print $4}')"
  if [ -n "$avail_kb" ] && [ "$avail_kb" -lt $((12 * 1024 * 1024)) ]; then
    die "only $((avail_kb / 1024 / 1024)) GiB free on $BUILD_DIR — need at least 12 GiB"
  fi
fi

# --- root --------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  need sudo "mkarchiso must run as root"
  log "re-running under sudo"
  # Build the argument list explicitly: never rely on word splitting of a
  # command substitution to pass flags through to the privileged re-exec.
  reexec_args=(--work "$WORK_DIR" --out "$OUT_DIR")
  [ "$KEEP" = "1" ] && reexec_args+=(--keep)
  [ "$SKIP_CHECKS" = "1" ] && reexec_args+=(--skip-checks)
  exec sudo -E env \
    "CONTINUITY_ISO_BUILD_DIR=$BUILD_DIR" \
    "CONTINUITY_ISO_MKARCHISO=$MKARCHISO_CMD" \
    "$0" "${reexec_args[@]}"
fi

# From here on we are root.
log "work directory: $WORK_DIR"
log "output:         $OUT_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$PROFILE_DIR"

# --- 1b. CachyOS signing key -----------------------------------------------
# The profile's [cachyos] repo is signed by CachyOS's key. mkarchiso runs
# pacstrap with -G, which copies the build host's pacman keyring into the new
# root, so the key must be trusted here. The key ships in iso/keys/ and is
# checked against the fingerprint published at
# https://wiki.cachyos.org/cachyos_basic/download/ before it is added.
CACHYOS_KEY_FILE="$REPO_ROOT/iso/keys/cachyos.gpg"
CACHYOS_KEY_FPR="882DCFE48E2051D48E2562ABF3B607488DB35A47"
[ -f "$CACHYOS_KEY_FILE" ] || die "missing $CACHYOS_KEY_FILE"
need pacman-key "pacman is required on the build host"
need gpg "sudo pacman -S gnupg"

key_homedir="$(mktemp -d)"
key_fprs="$(gpg --homedir "$key_homedir" --batch --with-colons --import-options show-only \
  --import "$CACHYOS_KEY_FILE" 2>/dev/null | awk -F: '$1 == "fpr" {print $10}')"
rm -rf "$key_homedir"
# The primary key is the first fpr record; subkeys follow it.
[ "$(printf '%s\n' "$key_fprs" | head -n1)" = "$CACHYOS_KEY_FPR" ] || \
  die "CachyOS key fingerprint mismatch: expected $CACHYOS_KEY_FPR, got '$(printf '%s' "$key_fprs" | head -n1)'"

if [ ! -d /etc/pacman.d/gnupg ]; then
  pacman-key --init
fi
pacman-key --add "$CACHYOS_KEY_FILE"
pacman-key --lsign-key "$CACHYOS_KEY_FPR"
log "trusted CachyOS signing key $CACHYOS_KEY_FPR on the build host"

# --- 2. copy the profile -----------------------------------------------------
# rsync --delete is scoped to $PROFILE_DIR, which is inside $WORK_DIR, which we
# created above. Nothing else is ever pruned.
log "copying profile..."
# --delete is scoped to $PROFILE_DIR, which lives inside the $WORK_DIR we
# created above. Nothing else in the tree is ever pruned.
rsync -a --delete "$PROFILE_SRC/" "$PROFILE_DIR/"

# --- 3. embed the repository -------------------------------------------------
log "embedding the repository into airootfs/$ISO_PAYLOAD_DIR ..."
mkdir -p "$PROFILE_DIR/airootfs/$ISO_PAYLOAD_DIR"
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.freebuff/' \
  --exclude 'build/' \
  --exclude 'out/' \
  --exclude 'work/' \
  --exclude '*.iso' \
  "$REPO_ROOT/" "$PROFILE_DIR/airootfs/$ISO_PAYLOAD_DIR/"

# The payload ends up on the live medium at /opt/continuityos.
[ -f "$PROFILE_DIR/airootfs/$ISO_PAYLOAD_DIR/install.sh" ] || \
  die "repository copy failed: install.sh missing from the airootfs payload"

# --- 4. enable the live units ------------------------------------------------
# mkarchiso copies airootfs verbatim; it does not run `systemctl enable`. The
# repo cannot carry symlinks, so create them in the scratch copy here.
enable_unit() {
  local unit="$1" wants_dir="$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants"
  [ -f "$PROFILE_DIR/airootfs/etc/systemd/system/$unit" ] || {
    warn "cannot enable $unit — unit file not in the profile"; return 0; }
  mkdir -p "$wants_dir"
  ln -sfn "/etc/systemd/system/$unit" "$wants_dir/$unit"
  log "enabled $unit"
}
enable_unit continuity-live-boot.service

# mkarchiso installs packages into the scratch root with pacstrap and does not
# run the normal `systemctl preset`/enable phase. The live user session must
# wait until systemd-firstboot has initialized the first-boot machine identity;
# greetd.service.d/10-continuity-live.conf provides that ordering.
# The base system ships systemd-firstboot.service, which prompts on the first
# boot when /etc/machine-id is uninitialized. Do not mask it: archiso wants the
# first boot setup to run; instead the greetd drop-in waits for it to finish.
log "left systemd-firstboot.service enabled for live-system initialization"

# A unit that comes from a *package* cannot be checked on the build host — the
# package is not installed here — so the check is against packages.x86_64: if the
# package is in the medium's list, the unit will exist in the built root and
# systemd resolves this symlink at boot. (The check this replaces looked for
# airootfs/usr/lib/systemd/system/NetworkManager.service, a path that only exists
# after the pacman transaction, so it could never fire and the live medium came
# up without networking.)
enable_packaged_unit() {
  local unit="$1" pkg="$2" wants_dir="$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants"
  if [ -e "$PROFILE_DIR/airootfs/usr/lib/systemd/system/$unit" ]; then
    : # shipped by the profile itself
  elif grep -qx "$pkg" "$PROFILE_SRC/packages.x86_64" 2>/dev/null; then
    : # the pacman transaction installs it into the new root
  else
    warn "not enabling $unit — no '$pkg' in packages.x86_64 and no unit in airootfs"
    return 0
  fi
  mkdir -p "$wants_dir"
  ln -sfn "/usr/lib/systemd/system/$unit" "$wants_dir/$unit"
  log "enabled $unit (provided by $pkg)"
}

# Networking is what makes a live install possible at all.
enable_packaged_unit NetworkManager.service networkmanager

# greetd is what turns this medium into a ContinuityOS desktop instead of a
# console: the boot hook writes /etc/greetd/config.toml with an [initial_session]
# that runs the session with no greeter. getty@tty1 is deliberately NOT masked —
# greetd's own unit already Conflicts= with it, and masking it would remove the
# recovery path a broken session needs.
enable_packaged_unit greetd.service greetd

# --- 5. build ----------------------------------------------------------------
log "running mkarchiso (this takes a while)..."
set +e
"$MKARCHISO_CMD" -v -w "$MKARCHISO_WORK" -o "$OUT_DIR" "$PROFILE_DIR"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  warn "mkarchiso failed with status $rc"
  warn "the scratch tree is preserved at $WORK_DIR for inspection"
  exit "$rc"
fi

# --- 6. report ---------------------------------------------------------------
iso_file="$(find "$OUT_DIR" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null \
  | sort -n | tail -n1 | cut -d' ' -f2-)"
[ -n "$iso_file" ] || die "mkarchiso succeeded but no .iso was found in $OUT_DIR"

# Validate the artifact, not only the profile declaration. UEFI systemd-boot
# produces one FAT EFI system partition, used by the UEFI El Torito entry. The
# image may still have a generic isohybrid MBR/GPT layout for USB-writing tools;
# what must never be present is a BIOS El Torito boot image. A hybrid MBR is
# partition-table compatibility metadata, not a Legacy BIOS boot path.
boot_report="$(xorriso -indev "$iso_file" -report_el_torito plain -report_system_area plain -end 2>&1)" || {
  printf '%s\n' "$boot_report" >&2
  die "xorriso could not inspect the built ISO's boot metadata"
}
uefi_entries="$(printf '%s\n' "$boot_report" | grep -Ec 'El Torito boot img.*UEFI' || true)"
[ "$uefi_entries" -eq 1 ] || {
  printf '%s\n' "$boot_report" >&2
  die "expected exactly one UEFI El Torito boot entry, found $uefi_entries"
}
if printf '%s\n' "$boot_report" | grep -Eq 'El Torito boot img.*BIOS'; then
  printf '%s\n' "$boot_report" >&2
  die "built ISO contains a legacy BIOS El Torito boot entry"
fi
if printf '%s\n' "$boot_report" | grep -Eq 'GPT partition path.*isolinux|GPT partition path.*syslinux'; then
  printf '%s\n' "$boot_report" >&2
  die "built ISO contains a legacy BIOS/syslinux boot partition"
fi
printf '%s\n' "$boot_report" | grep -Fq '28732ac11ff8d211ba4b00a0c93ec93b' || {
  printf '%s\n' "$boot_report" >&2
  die "built ISO has no GPT EFI System Partition"
}
log "verified one UEFI El Torito entry and a GPT EFI System Partition; no BIOS boot entry"

if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$OUT_DIR" && sha256sum "$(basename "$iso_file")" > SHA256SUMS )
  log "wrote $OUT_DIR/SHA256SUMS"
fi

size="$(du -h "$iso_file" | cut -f1)"
log "done: $iso_file ($size)"

if [ "$KEEP" != "1" ]; then
  log "scratch tree left at $WORK_DIR (delete it yourself when you are done)"
fi

cat <<EOF

Next steps
  1. Write to a USB stick:   sudo dd if='$iso_file' of=/dev/sdX bs=4M status=progress oflag=sync
  2. Verify it first:        sha256sum -c '$OUT_DIR/SHA256SUMS'
  3. Boot it: the medium comes up as a ContinuityOS desktop (autologin, no
     greeter) with the guided installer on screen.
  4. The ISO is unsigned — see iso/README.md before distributing it.
EOF
