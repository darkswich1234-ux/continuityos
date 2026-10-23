# Building the ContinuityOS ISO

The ISO is an **archiso profile**, not a release distribution. It produces a live
medium that boots into the ContinuityOS desktop and contains everything needed to
install that same system onto a disk. Read the caveats at the bottom before you
hand the image to anyone.

## Requirements

| | |
|---|---|
| Host | Arch Linux (or an Arch-based host) with `archiso` installed |
| Packages | `archiso`, `rsync`, `libisoburn`, `squashfs-tools`, `zstd`, `git`, `base-devel` |
| Disk | ~12 GiB scratch + ~3 GiB for the finished ISO |
| Privileges | root (the builder re-executes itself through `sudo` automatically) |
| Network | required — `mkarchiso` performs a full pacman transaction |

```bash
sudo pacman -S --needed archiso rsync libisoburn squashfs-tools zstd
./iso/build.sh
```

Output lands in `build/out/continuityos-<version>-x86_64.iso`, with
`build/out/SHA256SUMS` next to it. Override the locations with `--work`/`--out`
or `CONTINUITY_ISO_BUILD_DIR=/mnt/big/continuity ./iso/build.sh`.

Watch the build with `--keep` if you want the scratch tree; on failure it is
always kept, and the tree is at `build/work/` (the profile copy at
`build/work/profile`, mkarchiso's own work dir at `build/work/mkarchiso`).

## What the builder does

1. Pre-flight: checks `mkarchiso`, the profile layout, kernel/boot-stanza
   agreement, boot-mode spelling against the installed archiso, free space, and
   that the files the live desktop depends on are present (the boot hook, the
   live account, the greetd ordering drop-in).
2. Copies `iso/profile/` into the scratch directory (`rsync -a --delete`, scoped
   to the scratch copy — your checkout is never modified).
3. Embeds the whole repository into `airootfs/opt/continuityos`, which is the
   payload the live session installs from. Build output directories (`build/`,
   `.git/`, `.freebuff/`) are excluded.
4. Creates the systemd `wants` symlinks for `continuity-live-boot.service`,
   `NetworkManager.service` and `greetd.service` (mkarchiso copies `airootfs`
   verbatim and does not run `systemctl enable`, and symlinks cannot be
   represented in the repo).
5. Runs `mkarchiso -v -w <work> -o <out> <profile copy>`.
6. Prints the ISO path and writes `SHA256SUMS`.

## Layout

```
iso/
├── build.sh                     the builder (this document's subject)
└── profile/
    ├── profiledef.sh            iso name/label, UEFI-only bootmode, file_permissions
    ├── packages.x86_64          live-medium package list (grouped by purpose)
    ├── pacman.conf              build transaction config — [multilib] REQUIRED
    ├── efiboot/loader/          systemd-boot entries for the UEFI path (the only boot path)
    └── airootfs/                files copied into the live root
        ├── root/.automated_script.sh                live boot hook
        ├── etc/sysusers.d/continuity-live.conf      the live account
        ├── etc/sudoers.d/continuity-live            its passwordless sudo
        ├── etc/systemd/system/                      continuity-live-boot.service
        │                                            greetd.service.d/10-continuity-live.conf
        └── etc/systemd/system/continuity-first-boot.service.d/override.conf
```

## Booting the live medium

The image is **UEFI-only** and starts systemd-boot from the EFI system partition.
There is no Legacy BIOS or syslinux boot path. The menu offers two entries; the
live desktop is the default:

| Entry | Use |
|---|---|
| ContinuityOS (live desktop) | Normal boot. Comes up as a ContinuityOS desktop with the guided installer on screen. Everything is in RAM (`cow_spacesize=12G`). |
| ContinuityOS (automatic install) | Same desktop, plus `continuityos.install=1`. Add `continuityos.disk=/dev/nvme0n1` to the options line to make it unattended — see below. |

There is **no greeter and no text login**. `greetd` runs an `[initial_session]`
for the live account (`continuity`), so the desktop is the first thing on screen —
the same shape as an installed system, and the reason this medium exists.

Once booted, the installer is already open. From a console (Ctrl+Alt+F2) the same
thing is reachable as:

```bash
/opt/continuityos/bin/continuity-installer ui        # the guided flow
/opt/continuityos/bin/continuity-installer disks     # what it would offer
/opt/continuityos/bin/continuity-installer status    # live medium? archinstall version?
/opt/continuityos/bin/continuity-installer plan \
    --disk /dev/nvme0n1 --user you --host continuity \
    --timezone Europe/London --locale en_GB.UTF-8    # generate the config, touch nothing
```

`plan` writes the archinstall config into `--out` and prints what would happen.
It is the right first command on a machine you care about: it refuses the same
disks `install` refuses, and it changes nothing.

## The disk install

The installer splits the work deliberately:

* **archinstall** does what must not be improvised — partitioning, `mkfs`, the
  base system, the `linux-zen` kernel, `systemd-boot`, the account.
* **the payload's own `install.sh`** then runs inside the target's chroot and
  installs the ContinuityOS stack: the desktop, the gaming stack, the 32-bit
  libraries and the graphics drivers for the GPU actually detected. The package
  lists and the GPU detection therefore live in exactly one place and cannot
  drift from what an installed system gets.
* **`continuity-boot`** is run last inside the target, which is what makes the
  installed machine boot straight into the desktop with no login prompt.

The layout it produces is fixed and simple: GPT, a 512 MiB FAT32 ESP at `/boot`,
and one ext4 (or btrfs, with a `@` subvolume) root taking the rest of the disk.
Everything on the chosen disk is erased. There is no encryption, no LVM, no
dual boot, and no BIOS support — for any of those, run `archinstall` by hand.

Safety, in order of how much it matters:

* the disk must be a whole disk, at least 20 GiB, not removable, and must have
  nothing mounted on it;
* the medium itself is never offered — it is found from `/run/archiso` and from
  what is mounted, and both are refused;
* the device name has to be typed back before anything is written;
* `--yes` on its own is **not** enough; an unattended run also needs
  `continuityos.disk=` on the kernel command line, i.e. someone asked for it;
* after archinstall returns, the installer proves the install happened — a root
  filesystem with `ID=arch`, the account in `/etc/passwd`, a bootloader, the
  ContinuityOS session, and `/usr` with a real package set — and reports a
  failure as a failure. A silent run that exits 0 without installing is
  explicitly detected and named, because archinstall can do that.

### Kernel command-line parameters

| Parameter | Meaning |
|---|---|
| `continuityos.install=1` | Ask the boot hook to start an install. On its own it launches the guided installer (the same thing you already see on the desktop). |
| `continuityos.disk=/dev/…` | The disk to erase, unattended. Required for a hands-off install; without it the installer asks. |
| `continuityos.user=NAME` | Account to create (default `continuity`). |
| `continuityos.host=NAME` | Hostname (default `continuity`). |
| `continuityos.install=1 continuityos.disk=/dev/nvme0n1` | The full unattended form: partition that disk, install, set up autologin, log to `/var/log/continuity-installer.log`. |

`--dry-run` is available on `install.sh` for the package phase, but there is no
dry run for partitioning: the whole point of `plan` is to be the thing you read
first.

## How the installed system gets configured

`install.sh` remains the single entry point in every mode, and the disk install
calls it in the target rather than reimplementing it. Two details of that handoff
are worth knowing:

* **Target user.** `install.sh` reads the account from `--target-user` (the
  installer passes the one archinstall created) or from
  `/etc/continuity/install.conf`. Note that `--user NAME` is *not* accepted
  together with `--system`/`--all`: it selects `--user` mode. Use
  `--target-user NAME` there.
* **Runtime seeding.** The `continuity-first-boot.service` drop-in orders
  first-boot work after `continuity-umu-seed.service`, so the Steam Linux Runtime
  is validated before a user's first double-clicked `.exe`. If no runtime is
  bundled on the medium, `--seed` finds no local source and umu downloads the
  runtime on the first game launch instead — on the live medium that is why
  provisioning is quick.

## Caveats — read before distributing

* **It has never been booted.** The desktop session, the greetd autologin, the
  installer and the whole disk path in this repository have been written and
  reviewed but never executed: no ISO has been built here, no disk has been
  partitioned, and archiso's boot-mode spellings are version-sensitive. Treat
  `plan` plus a scratch machine as the first real test, not the ISO itself.
* **archinstall's config schema is version-sensitive.** `bin/continuity-installer`
  writes the 3.x field names (`disk_config` with
  `config_type: manual_partitioning`, `bootloader_config`, `locale_config`, and
  users in the `--creds` file). Upstream has since moved on. The installer
  detects the major version, says which field names it generated and which
  version it found, and refuses to claim success without verification — but a
  different schema will fail somewhere visible, not silently.
* **UEFI only.** The generated layout assumes UEFI; a legacy-BIOS boot is refused
  with an explanation rather than half-installed.
* **It is unsigned.** There is no signing key, no Secure Boot chain, no
  reproducible-build attestation. Anyone who has the file can change it. Do not
  present it as a verified image.
* **No release engineering.** This profile builds a working medium from current
  Arch packages; it is not a snapshot with a security response process. Two
  builds a week apart are different operating systems in practice.
* **`bootmodes` is version-sensitive.** The build checks the installed archiso
  releng profile for the UEFI systemd-boot spelling and stops before building if
  that spelling is unsupported.
* **Kernel flavour is hardcoded in the UEFI boot entry.** The profile ships
  `linux-zen`, so systemd-boot references `vmlinuz-linux-zen` /
  `initramfs-linux-zen.img`. Swapping the kernel package without editing
  `efiboot/loader/entries/*.conf` yields an ISO that fails to boot.
* **The live session runs as an unprivileged account.** That is what makes it a
  desktop, and it is also why the medium ships a passwordless-sudo rule for
  `continuity` in `airootfs/etc/sudoers.d/`. Nothing installs that rule onto a
  target: `install.sh --system` never copies `iso/profile/airootfs/etc` anywhere.
* **ARM is not covered by this profile.** `arch="x86_64"` is hardcoded
  throughout archiso's tooling and this profile. The 32-bit *userspace* libraries
  (`lib32-*`, multilib) that the compatibility engine needs are unrelated to
  running ContinuityOS on ARM hardware; that would be a separate aarch64 profile.
