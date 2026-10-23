# The engine on any Linux install (no ISO, no reinstall)

ContinuityOS used to be two things: an engine that runs Windows programs through
Proton, and an opinionated Arch desktop around it (Hyprland shell, greetd
autologin, a live medium that installs to a disk). This document is about using
**only the engine** on the Linux you already run — Debian/Ubuntu, Fedora, Arch,
or a remix such as infinityOS.

```bash
git clone <this repository> && cd ContinuityOS
./standalone/install.sh            # ~/.local, no root
proton check                       # what is missing on this machine?
proton ~/Downloads/GameSetup.exe   # run a Windows program
```

Nothing is partitioned, no bootloader is touched, no session or display manager
changes, no package repository is added, and no file outside your account (or
`/usr/local`, with `--system`) is written.

## What it installs

| | |
|---|---|
| `~/.local/bin/proton` | the command: run a `.exe`, list/inspect/remove prefixes, run the readiness check |
| `~/.local/bin/continuity-run` | the launcher `proton` delegates to (`--print-env`, `--direct`, `--native`, …) |
| `~/.local/bin/continuity-prefix` | prefix manager (`list`, `info`, `rm`, `export`, `launchers`) |
| `~/.local/bin/continuity-shakedown` | the readiness report behind `proton check` |
| `~/.local/lib/continuity/continuity-common.sh` | paths, slugs, prefix layout, distribution detection |
| `~/.local/bin/umu-run` | the Proton runtime launcher, from the upstream umu-launcher release (only when the machine has none) |
| `~/.config/continuity/environment.conf` | engine tuning, only written when you have none |
| `~/.local/share/applications/continuity-wine.desktop` | the `.exe` handler, plus the MIME defaults that make double-click work |

`sudo ./standalone/install.sh --system` puts the same files in `/usr/local`,
installs the handler in `/usr/local/share/applications` and the defaults in
`/etc/skel` for new accounts, and does not set a MIME default for root.

## Requirements

- x86_64 Linux with a working desktop and Vulkan driver.
- `python3` (umu-launcher is a Python application), `tar`, and `curl` or `wget`.
  `--with-deps` installs the missing ones with the system package manager.
- Network **on the first launch**: `umu-run` downloads the matching Proton build
  and the Steam Linux Runtime into `~/.local/share/umu` (about 1 GB, once).
- Wine is optional. Install it for `.msi`/`.lnk` and for `proton --native`:
  `./standalone/install.sh --with-wine` or your distribution's package.

## Usage

```bash
proton GameSetup.exe                     # own prefix, derived from the file name
proton --installer GameSetup.exe         # install, then register launchers
proton --name mygame Game.exe            # choose the prefix name yourself
proton --native legacy-tool.exe          # system Wine instead of Proton
proton --print-env Game.exe              # resolved environment, launch nothing

proton list                              # prefixes on this machine
proton info mygame                       # path, size, executables, launchers
proton rm mygame                         # delete prefix + launchers
proton export mygame mygame.tar.zst      # archive it
proton import mygame.tar.zst mygame      # restore it

proton check                             # Vulkan, Wine, Proton, umu readiness
proton version                           # what is installed where
proton uninstall                         # remove the command (not your prefixes)
```

A prefix is a directory and a Wine prefix, nothing more:

```
~/.local/share/universal-prefixes/<slug>/
    pfx/drive_c/...
```

One broken game only ruins its own directory, and removing it leaves no registry
or DLL residue behind (`proton rm <slug>`).

## Distribution notes

| Family | What the installer does | 32-bit note |
|---|---|---|
| Debian / Ubuntu / infinityOS | user-local install; `umu-run` zipapp from upstream (no repository package exists) | 32-bit games need `sudo dpkg --add-architecture i386` and the `:i386` graphics drivers — `proton check --fix` prints the exact line |
| Fedora / Nobara | `umu-launcher` from the repository where it exists, otherwise the zipapp | use the `.i686` driver packages |
| Arch / CachyOS | `umu-launcher` from `[multilib]` where installed, otherwise the zipapp | `lib32-*` packages, as before |
| openSUSE / other | the zipapp plus a warning naming what to install with `zypper` | depends on the vendor repository |

The installer detects the family from `/etc/os-release` (falling back to the
package manager it finds) and everything that prints a "how do I fix this"
command — `proton check`, a missing `umu-run`, a missing Wine — speaks that
family's package manager instead of assuming `pacman`.

## Verify

```bash
proton check                 # exit 1 when a hard check fails
proton check --json          # the same report, machine readable
proton --print-env x.exe     # the full launch environment, without launching
```

The installer runs both of these itself at the end, against a throwaway prefix
root, so a broken install is reported instead of silently succeeding.

## Uninstall

```bash
proton uninstall             # command, handler, PATH block; prefixes and config stay
proton uninstall --purge     # ... and delete ~/.config/continuity and every prefix
```

`sudo ./standalone/install.sh --system --uninstall` removes a system-wide
install. Files in the target directory that this project did not create are
never overwritten without `--force`.

## Why the installer downloads umu-run itself

`umu-launcher` is not packaged by Debian, Ubuntu or Fedora (Nobara and Arch have
it; Debian/Ubuntu have unpackaged `.deb` releases). The upstream zipapp is the
route the project documents for generic distributions, so the installer reads
the latest release from the GitHub API, **verifies the published SHA-256**, and
installs it as `umu-run` next to the other commands. `--engine /path/to/umu-run`
uses an existing one instead, and `--no-download` skips the step entirely.

## Troubleshooting

- **`umu-run not found`** — the download was skipped or failed. Re-run
  `./standalone/install.sh`, or install it however your distribution prefers and
  make sure `umu-run` is on `PATH`.
- **`env: 'bash\r': No such file or directory`** — the scripts came from a
  Windows checkout with CRLF line endings. The installer rewrites the files it
  installs, so re-running it fixes an existing install; source files in the
  repository are kept LF.
- **First launch takes minutes** — that is Proton and the Steam Linux Runtime
  downloading. Later launches are local.
- **A game fails after an update** — `proton rm <slug>` and install it again in
  a fresh prefix; the rest of your prefixes are untouched.

## What this does not do

No desktop shell, no gaming mode, no autologin, no disk installer, no package
repository, no systemd units, no `/etc` files. If you want the full ContinuityOS
desktop, that is [INSTALL.md](INSTALL.md) (live medium, Arch) or
`sudo ./install.sh --all` on an existing Arch install.
