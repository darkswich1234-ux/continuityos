# proton — run Windows programs through Proton, on any Linux

The ContinuityOS engine on its own: one command that runs a Windows `.exe` in its
own Proton prefix. No ISO, no desktop environment, no distribution of its own, and
nothing else about the machine changes.

```bash
sudo ./install.sh                      # install for every user (/usr/local)
proton check                           # is this machine ready for Windows games?
proton ~/Downloads/GameSetup.exe       # run one, in its own prefix
```

## Install

| How | Command | Where it goes |
|---|---|---|
| Root level, every user | `sudo ./install.sh` | `/usr/local/bin`, `/usr/local/lib/continuity`, `/usr/local/share/applications`, `/etc/skel` for new accounts |
| This account only | `./install.sh` | `~/.local/bin`, `~/.local/lib/continuity`, `~/.local/share/applications` |
| Preview | `./install.sh --dry-run` | prints every action, changes nothing |
| Remove | `sudo ./install.sh --uninstall` (or `proton uninstall`) | prefixes and config are kept unless `--purge` |

Useful flags: `--user` (force a per-account install even as root), `--with-wine`
(Wine for `.msi`/`.lnk` and `--native`), `--with-deps` (install missing
prerequisites with the system package manager), `--engine PATH` (use an existing
`umu-run`), `--no-download`, `--no-desktop`, `--no-path`, `--force`.

The installer detects the distribution and installs `umu-run` from the upstream
umu-launcher release (SHA-256 verified) when the distribution has no package for
it. The Proton build itself and the Steam Linux Runtime are downloaded by
`umu-run` on the first launch (~1 GB, once).

## Use

```bash
proton GameSetup.exe                     # own prefix, named after the file
proton --installer GameSetup.exe         # install, then register launchers
proton --name mygame Game.exe            # choose the prefix name
proton --native legacy-tool.exe          # system Wine instead of Proton
proton --print-env Game.exe              # resolved environment, launch nothing

proton list                              # prefixes on this machine
proton info mygame                       # path, size, executables, launchers
proton rm mygame                         # delete prefix + launchers
proton export mygame mygame.tar.zst      # archive a prefix
proton import mygame.tar.zst mygame      # restore one

proton check [--json] [--probe]          # Vulkan, 32-bit, Wine, Proton, UMU
proton version                           # engine, umu-run, prefix locations
```

A prefix is just a directory, so one broken game only ruins its own:

```
~/.local/share/universal-prefixes/<slug>/
    pfx/drive_c/...
```

## Requirements

- x86_64 Linux with a working desktop and Vulkan driver.
- `python3`, `tar`, and `curl` or `wget` (`--with-deps` installs what is missing).
- Network on the first launch, for the Proton build and the Steam Linux Runtime.
- Wine is optional: needed for `.msi`, `.lnk` and `proton --native`.
- 32-bit games need the distribution's i386 stack — `proton check --fix` prints the
  exact command for the release you run.

## Distribution notes

| Family | Engine install | 32-bit for older games |
|---|---|---|
| Debian / Ubuntu / infinityOS | user or root install; `umu-run` zipapp from upstream (no repository package exists) | `sudo dpkg --add-architecture i386`, then the `:i386` graphics drivers |
| Fedora / Nobara | `umu-launcher` from the repository where it exists, otherwise the zipapp | the `.i686` driver packages |
| Arch / CachyOS | `umu-launcher` from `[multilib]` where installed, otherwise the zipapp | the `lib32-*` packages |
| openSUSE / other | zipapp, with a warning naming what to install | depends on the vendor repository |

Everything that prints a remedy (`proton check`, a missing `umu-run`, a missing
Wine) uses the local distribution's package manager instead of assuming `pacman`.
See [docs/ENGINE.md](docs/ENGINE.md) for the details and troubleshooting.

## Repository layout

```
install.sh                 the installer (root level by default when run as root)
bin/proton                 the command: run, prefixes, check, uninstall
bin/continuity-run         the launcher `proton` delegates to
bin/continuity-prefix      prefix manager
bin/continuity-shakedown   the readiness report behind `proton check`
lib/continuity-common.sh   paths, slugs, prefix layout, distribution detection
config/environment.conf    engine defaults, copied on install
docs/ENGINE.md             how it works, per-distribution notes, troubleshooting
tests/run.sh               offline checks; run them after any change
```

## Status

The installer, the command, prefix management and the readiness report are covered
by `tests/run.sh` (offline, no root, no network) and were exercised end to end on a
Debian-family system: install, re-install, `proton` commands, uninstall, root-level
install, CRLF checkouts and refusing to overwrite files it did not create. A real
Proton launch is the one thing that cannot be proven off the target machine — it
needs the GPU and the first-launch runtime download.
