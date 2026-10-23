# Installing ContinuityOS to a disk

This is the difference between "a profile you apply to an Arch box" and "an
operating system you install". Until this existed the live medium could not install
anything: `continuityos.install=1` ran `install.sh --all` *inside the live RAM
system*, which configures a machine that forgets everything on reboot. That is why
the only way to run ContinuityOS was to install plain Arch first and then apply the
profile — exactly the `Arch → Hyprland → ContinuityOS` path this repository is meant
to remove.

Now the medium boots into the ContinuityOS desktop as a live user and the thing on
screen is a **guided disk install**.

## Before you start

| | |
|---|---|
| Firmware | **UEFI.** The generated layout is GPT + a FAT32 ESP + `Systemd-boot`. Legacy BIOS boot is refused at install time with a message saying so (a `plan` still prints, so you can read it anywhere). |
| Disk | A whole disk, ~20 GiB minimum, that you are willing to erase. No dual boot, no LUKS, no LVM — those are refused rather than half-done. |
| Network | Recommended: the target's packages come from the Arch repos. |
| Boot order | Boot the UEFI-only medium; systemd-boot entries are in `iso/profile/efiboot/loader/entries/`. Legacy BIOS is not supported. |

## Guided install (what the medium opens for you)

```bash
continuity-installer ui          # or: the installer window on the live desktop
continuity-installer disks       # what it can see: device, size, model, removable, in use
```

It asks, in order: which disk (with sizes and models), hostname, your account name,
a password (twice, hidden), time zone, locale, keyboard layout, filesystem
(`ext4` or `btrfs` with a `@` subvolume), and finally it makes you **type the device
name back** before it writes anything. Cancel at any point leaves the machine
untouched.

## Unattended install (kernel parameters)

The `continuityos.install=1` boot entry — and the same parameters typed by hand —
now mean something true:

| Parameter | Meaning |
|---|---|
| `continuityos.install=1` | with a disk below: run the installer with no questions. **Without** a disk: it does not guess, it opens the guided installer on the desktop and says why. |
| `continuityos.disk=/dev/nvme0n1` | the whole disk to erase. Required for an unattended run — `--yes` alone is refused, because "which disk" is the one question that must never be answered for somebody. |
| `continuityos.user=NAME` | the account to create (default: the live user). |
| `continuityos.host=NAME` | the hostname (default: `continuity`). |

Locale and time zone are taken from the live session. Progress goes to
`/var/log/continuity-install.log`; the desktop opens without the installer window
when the live hook has already started one.

## What it actually does, in order

1. **`archinstall`** partitions the disk and installs a *minimal* Arch: the
   `linux-zen` kernel, `networkmanager`, `git`, `rsync`, `sudo` and the tools needed
   to run the payload. Deliberately **not** the gaming stack — see the next point.
2. **Verify the target really exists.** archinstall's exit status is not trusted: a
   missing `disk_config` can make a silent run exit 0 having installed nothing. The
   installer probes the chosen disk's partitions read-only for `/etc/os-release`
   with `ID=arch`, and then checks that the account is in the target's `/etc/passwd`,
   that a bootloader exists under `/boot`, and that `/usr` is more than a token size.
   Any miss is a hard failure naming the log, with "archinstall exited 0 but nothing
   was installed" as its own message.
3. **Carry the payload over.** `/opt/continuityos` is copied from the live system
   into the target, so the desktop, the engine and this repository's own installer
   are on the machine it just created.
4. **`install.sh --all --yes --target-user NAME`** runs inside `arch-chroot`. This is
   the single source of truth for the ContinuityOS stack: GPU detection, `lib32-*`,
   `[multilib]`, host-native Proton integration, the Eww shell, the
   Wayland session, the `continuity-*` CLI, `/etc` files, pacman hooks and units.
   Nothing is duplicated in the installer.
5. **`continuity-boot on --user NAME`** inside the target, so the machine boots
   straight into the desktop (see [BOOT.md](BOOT.md)).
6. **Unmount, and print one instruction: reboot.**

## Passwords

The password is read from a `0600` file or prompted for with `read -rs`; it is never
an argument, so it cannot appear in `ps` or in the log. It is hashed into
`enc_password` (a `$6$` crypt hash from `openssl passwd -6`, or Python's `crypt`).
If neither is available the installer falls back to archinstall's deprecated
plaintext `"!password"` key **and says so on screen** — a deprecated key that works
beats a machine whose account cannot log in.

## The honest risk: archinstall's config schema

The generated `install-config.json` is written for archinstall **3.x**
(`disk_config` + `config_manual_partitioning`, `--config`/`--creds`/`--silent`,
`sector_size` on every `Size`). Upstream has moved to 4.x, and this schema has
changed between majors before. So the installer:

* detects the installed version and **warns loudly** when the major version is not
  one it knows how to generate config for, saying which field names it produced;
* refuses when `archinstall` is not installed at all, with the exact `pacman` line;
* never treats a zero exit status as success (step 2 above).

If the schema has moved, the fallback is the tool it wraps: run `archinstall` by hand,
boot the new system, copy this repository to it, and run
`sudo ./install.sh --all --yes`. That path is fully supported — it is how every
ContinuityOS machine has been built so far.

## On an existing Arch install (no reinstalling required)

ContinuityOS is a profile and automation layer, not a forked distribution: its
packages come from the Arch repos (and the AUR for extras), and
`pacman -Syu` keeps working because nothing pins versions. So this remains valid on
a machine you already run:

```bash
git clone <this repository> && cd ContinuityOS
sudo ./install.sh --all --dry-run    # read every action first
sudo ./install.sh --all              # packages, /etc, units, session, desktop, autologin
```

`--dry-run` is the right first command on a machine you care about. What you get
beyond the desktop is one thing: the boot now goes straight to ContinuityOS instead
of stopping twice on the way.

## What has not been verified

The whole disk path is **unbuilt and unbooted**: no ISO has been produced here, no
disk has been erased, `archinstall` has never been invoked, and `mkarchiso` has
never run. `plan`, its refusals, and the generated JSON are covered offline (the
suite drives them against a fixture `/sys/block` tree and a stub `lsblk`, and
validates the JSON), and that is the limit of what a machine without a spare disk
can prove. Treat the first real install as the first real test — on a disk you can
lose, with the boot log (`/var/log/continuity-install.log`) open in another VT.
