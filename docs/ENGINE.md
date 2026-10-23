# How the engine works

`install.sh` puts one command — `proton` — and its helpers on the machine. This
document is about what those files do, where they go, and what to do when a
Windows program will not start.

## What gets installed

| File | What it is |
|---|---|
| `<bin>/proton` | the command: run a `.exe`, list/inspect/remove prefixes, readiness check, uninstall |
| `<bin>/continuity-run` | the launcher `proton` delegates to (`--print-env`, `--direct`, `--native`, …) |
| `<bin>/continuity-prefix` | prefix manager (`list`, `info`, `rm`, `export`, `launchers`) |
| `<bin>/continuity-shakedown` | the readiness report behind `proton check` |
| `<lib>/continuity-common.sh` | paths, slugs, prefix layout, distribution detection |
| `<bin>/umu-run` | the Proton runtime launcher, from the upstream umu-launcher release (only when the machine has none) |
| `<config>/continuity/environment.conf` | engine defaults, only written when you have none |
| `<apps>/continuity-wine.desktop` | the `.exe` handler, plus the MIME defaults that make double-click work |

`<bin>`, `<lib>`, `<config>` and `<apps>` are `/usr/local/bin`,
`/usr/local/lib/continuity`, `/etc/skel/.config` and
`/usr/local/share/applications` for a root-level install, or
`~/.local/bin`, `~/.local/lib/continuity`, `~/.config` and
`~/.local/share/applications` for a single account.

A root-level install does not set a MIME default for `root` itself, and it never
edits a user's home directory: new accounts pick the configuration up from
`/etc/skel`.

## The launch path

1. `proton` resolves the target file into a slug (`GameSetup.exe` → `game-setup`)
   unless `--name` or `CONTINUITY_APP_NAME` says otherwise.
2. The slug maps to one directory under `$CONTINUITY_PREFIX_ROOT`
   (`~/.local/share/universal-prefixes` by default). Proton uses
   `<prefix>/pfx` as its Wine prefix.
3. `umu-run` boots Proton inside the Steam Linux Runtime, so nothing here needs
   Steam itself, a patched kernel, or a custom desktop. The runtime and the Proton
   build are downloaded into `~/.local/share/umu` on the first launch.
4. `--native` skips all of that and uses the distribution's Wine, which is also
   what `.msi` and `.lnk` files are routed through.
5. `--direct` runs a host-installed Valve Proton build without UMU (for people who
   already have Steam and prefer its runner).

`proton --print-env <file>` prints the whole resolved environment — slug, prefix,
engine, `PROTONPATH`, the command that would run — and launches nothing. That is
what the installer's own verification step uses.

## Configuration

`environment.conf` is sourced by every command, and only `CONTINUITY_*` keys are
honoured. It is ignored (with a warning) if it is not owned by you or is
group/world writable. The shipped defaults are documented in
[`config/environment.conf`](../config/environment.conf); the ones that matter most:

| Key | Meaning |
|---|---|
| `CONTINUITY_DEFAULT_ENGINE` | `umu` (default), `direct` (host Proton), `wine` |
| `CONTINUITY_PREFIX_ROOT` | where prefixes live |
| `CONTINUITY_PROTONPATH` | Proton build for `direct` mode |
| `CONTINUITY_GAMEID` | UMU/Steam-compatible app id (default `0`) |
| `CONTINUITY_AUTO_LAUNCHERS` | register launchers after every successful launch |
| `CONTINUITY_GAMESCOPE`, `CONTINUITY_MANGOHUD` | wrap launches in gamescope / MangoHud |

Command-line flags always win over the file.

## Distribution differences

`install.sh` and `proton check` both ask `lib/continuity-common.sh` what family the
machine is (from `/etc/os-release`, falling back to the package manager on PATH)
and build their advice from that:

| Family | Package manager used in remedies | 32-bit note |
|---|---|---|
| Debian / Ubuntu / infinityOS | `apt` (plus `dpkg --add-architecture i386` when a `:i386` package is involved) | i386 must be enabled before 32-bit graphics drivers can be installed |
| Fedora / Nobara | `dnf` | `.i686` driver packages |
| Arch / CachyOS | `pacman` | `[multilib]` must be enabled; `lib32-*` packages |
| openSUSE | `zypper` | vendor repositories |

`proton check` reports the 32-bit stack separately because a 64-bit game can run
perfectly while every 32-bit one fails with an error that names none of this.

## Why the installer downloads umu-run

`umu-launcher` is packaged by Arch and Nobara, but not by Debian, Ubuntu or
Fedora, so the installer uses the route upstream documents for generic
distributions: the zipapp from the latest GitHub release. It reads the release
metadata, installs the archive's `umu-run` next to the other commands, and
**verifies the published SHA-256** before installing it. `--engine /path/to/umu-run`
uses an existing one instead, and `--no-download` skips the step entirely.

## Uninstall

```bash
proton uninstall             # command, handler, PATH block; prefixes + config stay
proton uninstall --purge     # ... and delete the config and every prefix
sudo ./install.sh --uninstall   # equivalent for a root-level install
```

Only files this project created are removed. The PATH block the installer may have
added is fenced between `# >>> continuity engine` markers, and only that block is
deleted.

## Troubleshooting

- **`umu-run not found`** — the download was skipped or failed. Re-run
  `sudo ./install.sh` (or `./install.sh`), or install umu-launcher however your
  distribution prefers and make sure `umu-run` is on `PATH`.
- **`env: 'bash\r': No such file or directory`** — the scripts came from a Windows
  checkout with CRLF line endings. `install.sh` rewrites the files it installs, so
  re-running it repairs an existing install; the repository itself is stored with
  LF line endings via `.gitattributes`.
- **First launch takes minutes** — that is Proton and the Steam Linux Runtime
  downloading. Later launches are local.
- **A game breaks after an update** — `proton rm <slug>` and install it into a
  fresh prefix; the rest of your prefixes are untouched.
- **The desktop opens the wrong application for `.exe`** — `xdg-mime` was missing
  at install time. Install `xdg-utils` and re-run `install.sh`.
