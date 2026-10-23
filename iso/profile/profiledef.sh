#!/usr/bin/env bash
# shellcheck disable=SC2034
# ---------------------------------------------------------------------------
# ContinuityOS — archiso profile definition
#
# Sourced by mkarchiso. Every variable here is read by archiso; nothing in this
# file is executed as a script (so no logic, no command substitution that could
# fail on a weird locale — the two date calls are the only ones, and they are
# what releng itself uses).
#
# KERNEL NOTE: this profile ships **linux-zen**, so the systemd-boot entry in
# efiboot/loader/entries/*.conf must refer to vmlinuz-linux-zen /
# initramfs-linux-zen.img. archiso does not rewrite kernel names for you —
# swapping the kernel package without editing the entry produces an ISO that
# boots into "file not found".
# ---------------------------------------------------------------------------

iso_name="continuityos"
iso_label="CONTINUITYOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="ContinuityOS <https://github.com/continuityos>"
iso_application="ContinuityOS live medium — Universal Windows Compatibility Engine + Hyprland shell"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
arch="x86_64"

# ---------------------------------------------------------------------------
# Boot mode: UEFI/systemd-boot only. The installed Arch system is UEFI-only;
# this profile intentionally produces a clean EFI system partition plus UEFI
# El Torito entry, with no BIOS MBR or legacy syslinux path. This archiso
# version requires the UEFI systemd-boot mode by itself and adds neither BIOS nor
# syslinux artifacts when only this mode is selected.
# ---------------------------------------------------------------------------
bootmodes=('uefi.systemd-boot')

pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# ---------------------------------------------------------------------------
# file_permissions — ^^ where "uid:gid:mode" is applied by mkarchiso.
# Anything executable that lands in the airootfs must be listed here, otherwise
# mkarchiso logs a warning and the file keeps the mode of the checkout (which
# is 644 after a fresh clone on a filesystem that does not preserve exec bits).
# ---------------------------------------------------------------------------
# Every path listed here MUST exist in the airootfs, or mkarchiso complains.
# The /opt/continuityos entries are guaranteed by iso/build.sh step 3, which
# embeds this repository there before mkarchiso runs. The other entries belong to
# the live desktop: /etc/sudoers.d/continuity-live (the passwordless live account
# the graphical installer runs as) and the boot hook's own script.
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/opt/continuityos/install.sh"]="0:0:755"
  ["/opt/continuityos/bin"]="0:0:755"
  ["/opt/continuityos/iso/build.sh"]="0:0:755"
  # The guided installer is run straight out of the payload by the live session,
  # and the checkout it was rsynced from may not have carried the exec bit.
  ["/opt/continuityos/bin/continuity-installer"]="0:0:755"
  # sudo(8) ignores a sudoers file that is group- or world-writable, and the
  # live account needs passwordless sudo to write a disk.
  ["/etc/sudoers.d/continuity-live"]="0:0:440"
)
