# First-run wizard

The first time you log into ContinuityOS, a card in the middle of the screen greets
you and walks through eight short steps. It appears **once**, two seconds after the
shell is up, and it is entirely skippable — every step is also a command you can run
yourself at any time.

```
welcome ─▶ region ─▶ steam ─▶ transfer ─▶ windows ─▶ shakedown ─▶ mode ─▶ done
```

The order is deliberate. Language, keyboard, time zone and network come first,
because every later step is worse to do with a layout you cannot type with and no
connection; the engine check comes *after* the apps so it is checking something real.

| Step | What it does | Why it is there |
|---|---|---|
| **welcome** | Greets you by name and time of day, states where Windows programs will live and the keybinds worth knowing on day one. | A machine that explains itself beats a machine that has to be searched. |
| **region** | Language/region, keyboard layout, time zone, and joining a Wi-Fi network (via `continuity-region`). | Getting these wrong is the classic Arch first-boot regret, and a wrong layout makes every step after it miserable. |
| **steam** | Finds Steam libraries that exist on this machine but are not registered with Steam, and registers one. | This is the single biggest thing a Windows switcher has already: a library full of games on another drive that Steam has forgotten. |
| **transfer** | Saves this machine's setup to one archive, or brings one over from another ContinuityOS machine (via `continuity-export`). | Rebuilding forty prefixes and their launchers by hand is what stops people switching machines. |
| **windows** | Picks a `.exe`/`.msi`/`.lnk` and installs it into its own prefix, then registers launchers. | It demonstrates the compatibility engine working, on your own program, before you have to trust it. |
| **shakedown** | Reads this machine — GPU and driver, Vulkan, the 32-bit stack, Wine/Proton, and host Proton availability — and reports what is missing (via `continuity-shakedown`). `--probe` launches a real Windows program in a throwaway prefix. | Nothing else in the flow tells you whether games will actually *run*; a machine that fails here should say so on day one, not at the first launch. |
| **mode** | Balanced or Gaming as the *default* session style. | The two audiences of this OS want opposite defaults; ask once, changeable forever after. |
| **done** | Recaps every choice, including the ones you skipped, and where to find them again. | Nothing should disappear without a trace. |

## The two halves

`bin/continuity-wizard` is the engine and the whole brain. The Eww windows are only a
view.

* The engine works **headless**. With no Eww installed it prints page-by-page
  guidance and every step still completes from a TTY. A first-run flow that cannot be
  completed is worse than no flow at all.
* The view is **one Eww window per step**, and the names are contract: `wizard`,
  `wizard-region`, `wizard-steam`, `wizard-transfer`, `wizard-windows`,
  `wizard-shakedown`, `wizard-mode`, `wizard-done`. Eww's `:visible`
  attribute is a relatively recent addition, and a construct the installed Eww cannot
  parse would take the dock and the drawer down with it. One layer-shell surface per
  step costs nothing — only one is ever open — and works everywhere the rest of the
  shell works.
* The bridge is `config/eww/scripts/wizard.sh`, which polls the engine and turns
  machine values into sentences. Hyprland blurs the surfaces through
  `layerrule = blur on, match:namespace ^wizard`.

## State and markers

| Path | Contents |
|---|---|
| `~/.local/state/continuity/wizard.state` | `KEY=VALUE`, mode 0600. `PAGE`, `MODE`, `ERROR`; Steam: `STEAM_LIBRARY`, `STEAM_SUMMARY`, `STEAM_GAMES`, `STEAM_CANDIDATES`; app: `APP_NAME`, `APP_STATE`, `APP_PATH`; region: `REGION_LOCALE`, `REGION_KEYMAP`, `REGION_TIMEZONE`, `REGION_WIFI`, `REGION_SUMMARY`; check: `SHAKEDOWN_STATE`, `SHAKEDOWN_SUMMARY`, `SHAKEDOWN_HEADLINE`, `SHAKEDOWN_FIX`, `SHAKEDOWN_FAIL`, `SHAKEDOWN_WARN`; transfer: `TRANSFER_STATE`, `TRANSFER_ARCHIVE`, `TRANSFER_SUMMARY`. |
| `~/.local/state/continuity/wizard.done` | The completion marker, written by `finish` (or by skipping). Its existence is what stops the wizard from greeting you twice. |
| `~/.local/state/continuity/wizard-install.log` | Everything the Windows installer printed. This is where you look when an install reports failure. |

Two values are computed on demand rather than stored: `GREETING` (depends on the
clock and the user) and `PREFIX_ROOT` (depends on the environment).

## Reopening, resetting

```bash
continuity-wizard start              # resumes the remembered page
continuity-wizard start --force      # even after it was completed
continuity-panel wizard              # same thing from the shell
continuity-wizard goto shakedown     # jump straight to one step
continuity-wizard reset              # forget it; it greets you again at next login
continuity-wizard reset --purge-log  # ...and drop the installer log too
```

Each step is a command of its own, so none of this needs the card on screen:

```bash
continuity-wizard autodetect                   # apply the locale/keyboard/zone this machine reports
continuity-wizard pick-locale                  # zenity/rofi list of locales
continuity-wizard pick-keymap                  # ...of layouts
continuity-wizard pick-timezone                # ...of time zones
continuity-wizard wifi-join                    # pick a network, then type its password
continuity-wizard shakedown [--probe]          # readiness report (--probe launches a real program)
continuity-wizard transfer-export              # save this setup to ~/continuity-setup-*.tar.zst
continuity-wizard transfer-import [ARCHIVE]    # bring one over (asks for the file if omitted)
```

`continuity-panel wizard region` (likewise `shakedown`, `transfer`, `steam`,
`windows`, `mode`, or `wizard-page <page>`) opens the flow at that step. There is also
a *Welcome to ContinuityOS* entry in the app drawer.

Each of the three steps below delegates its real work to a separate tool, and the
wizard only holds the view of it — which is why every one of them works from a TTY
(`continuity-region`, `continuity-shakedown`, `continuity-export`).

## Language, keyboard, time zone, Wi-Fi

Unlike the Steam step, this one writes **your own** files, never another program's:

| What | Where | Why there |
|---|---|---|
| Keyboard layout | one fenced `input { kb_layout = … }` block in `~/.config/hypr/local.conf` | that is the file `hyprland.conf` sources last, so the layout wins without editing the shipped config |
| Locale and time zone | `~/.config/continuity/region.conf` **and** `~/.config/environment.d/10-continuity-region.conf` | the first is sourced by `continuity-shell` (so the compositor *and* everything it spawns — Proton, games — see `LANG`/`TZ`), the second reaches `systemd --user` services |

Everything here is **per-user by default**: no root, nothing outside `$HOME`. Making
it machine-wide (other accounts, a login screen) is deliberate:

```bash
continuity-region show                       # the seven values, with where each came from
continuity-region show --json
continuity-region locale en_GB.UTF-8
continuity-region keymap gb
continuity-region timezone Europe/London
continuity-region wifi scan
continuity-region wifi connect HomeNet       # reads the passphrase on stdin
sudo continuity-region locale en_GB.UTF-8 --system   # localectl/timedatectl, machine-wide
```

The Wi-Fi passphrase is read from **stdin**, never from an argument, so it cannot
appear in `ps` or in a log; it goes to `nmcli` in a mode-0600 file under the runtime
directory that is deleted even when the attempt fails. A missing `localectl`,
`timedatectl` or `nmcli` produces instructions, not a crash — and with no list to
choose from, the step falls back to `autodetect`, which applies what the machine
already reports rather than guessing a continent.

## Moving a setup between machines

```bash
continuity-export export                       # ~/continuity-setup-<host>-<date>.tar.zst
continuity-export export --out /media/usb/setup.tar.zst --dry-run
continuity-export inspect /media/usb/setup.tar.zst
continuity-export import /media/usb/setup.tar.zst --dry-run
continuity-export import /media/usb/setup.tar.zst
continuity-export list                         # what is here, with sizes
```

The archive holds the Windows prefixes, their generated launchers and icons, the
wizard's state, the gaming-mode marker and your engine preferences. It is a plain
tar stream and it is verified: the manifest records what was packed and a
`sha256sum` list covers every file, and **import verifies the checksums before it
writes anything** — a tampered or truncated archive changes nothing on your machine.
Compression is detected from the content, not the filename, so an archive written on
a machine without `zstd` (gzip inside a `.tar.zst` name) still imports.

What it will not do:

* **Overwrite quietly.** The default is a merge: an existing prefix or launcher is
  kept and reported as skipped. `--replace` is the explicit version, and it moves the
  current copy aside to `~/.local/state/continuity/replaced/` rather than deleting it.
* **Leave launchers pointing at the old machine.** Every imported launcher's
  `Exec=`, `Path=` and `Icon=` is rewritten from the archive's recorded home to yours.
* **Claim to move Steam.** Steam, Valve Proton installations and game libraries are
  *not* in the archive — they are machine state. After importing, install Steam and a
  Proton version, then register the library in place with `continuity-wizard import-steam`.

## Will games actually run?

This is the step that answers the question no installer usually answers:

```bash
continuity-shakedown            # one STATUS key detail line per check, then a summary
continuity-shakedown --quiet    # only what needs attention
continuity-shakedown --fix      # ...plus the exact command that fixes each problem
continuity-shakedown --json     # for scripts
continuity-shakedown --probe    # create a throwaway prefix and launch a real Windows program
continuity-shakedown --prune    # remove a leftover probe prefix
```

| Status | Means |
|---|---|
| `PASS` | working |
| `WARN` | not a verdict: no Steam Proton build selected yet, no `gamescope`, or missing Wine for `.msi`/`.lnk` handling |
| `FAIL` | a hard blocker, with the package that fixes it in `--fix` |
| `SKIP` | cannot be determined here (not an Arch system, no `/usr/lib32`, no EFI) |

Exit codes are honest: `0` when nothing failed, `1` when something did, `2` for a
usage error — which is what lets the card colour itself (`SHAKEDOWN_STATE` is
`pass`/`warn`/`fail`/`unknown`, and the Eww window turns that into a chip). A clean
machine says so in words rather than rendering an empty bullet.

## Steam library import: what it will and will not do

This is the only step that edits a file owned by another program, so it is written to
refuse rather than to guess.

**What it does**

1. Reads the libraries Steam already knows about from
   `<steam>/steamapps/libraryfolders.vdf`.
2. Finds candidates by looking for `steamapps` directories up to three levels deep on
   real mounts (`tmpfs`, `proc`, `sysfs` and similar are skipped), requiring at least
   one installed game — an empty leftover folder is not offered. Steam roots checked:
   `~/.steam/steam`, `~/.local/share/Steam`, `~/.steam/root`, `/usr/share/steam`, and
   the Flatpak path `~/.var/app/com.valvesoftware.Steam/data/Steam`.
3. Backs the library list up to `<file>.continuity-backup`.
4. Inserts exactly one new numbered entry (a `path`/`label`/`totalsize` block) into
   that list, and reports how many games the library holds by counting
   `appmanifest_*.acf` files.

**What it refuses to do**

* It refuses while **Steam is running**, because Steam rewrites that list when it
  exits and would silently discard the change.
* It refuses to write at all unless the result is still well-formed: the brace count
  must balance **and** exactly one library entry must have been added. If either check
  fails it leaves the original file untouched and says so. (Comparing raw brace
  *characters* would reject every valid insert, since a new block adds one opening and
  one closing brace — the check compares balance and entry count instead.)
* It never moves, copies or deletes a game file.
* Importing a library that is already registered is a no-op, not a duplicate entry.

```bash
continuity-wizard scan-steam            # what it can see, with game counts and names
continuity-wizard scan-steam --json     # machine-readable for scripts
continuity-wizard import-steam /mnt/games/SteamLibrary
continuity-wizard import-steam --first  # the first unregistered library (one-tap button)
```

ContinuityOS never touches `steamapps/compatdata` — Steam's own prefixes are Steam's
business.

## Balanced or Gaming

`set-mode` does two things:

1. It writes `CONTINUITY_START_IN_GAMING_MODE=0` or `=1` into
   `~/.config/continuity/environment.conf`, **preserving the comments in that file**
   (it is documentation as much as configuration — the comments explain every other
   key).
2. It applies the change to the session you are looking at, immediately, via
   `continuity-gaming-mode`.

At login, `continuity-session-start` starts lean if *either* the configured default is
`1` *or* a leftover `~/.local/state/continuity/gaming-mode.enabled` marker is present
(the marker is what a mid-session `Super+G` leaves behind). `Super+G` and the
Performance tile in Quick Settings override it live at any time.

Gaming mode deliberately does **not** close the wizard while it is open: a user who
taps "Gaming" in the middle of setup should not watch the card vanish. To close the
wizard too, use `continuity-panel hide-all --with-wizard`.

## Installing your first Windows program

`install-exe` looks for a file chooser in this order: `zenity`, `kdialog`, `yad`,
`qarma`. With none installed it falls back to the newest `.exe`/`.msi` in
`~/Downloads` or `~/Desktop` and tells you how to fix the missing chooser
(`sudo pacman -S zenity`).

The installer then runs **detached** — some Windows installers take many minutes, and
the wizard must stay responsive — with all output going to `wizard-install.log`. A
poll watches the process; once it exits, the prefix is scanned and launchers are
registered in the app drawer and the dock. The prefix lives at
`~/.local/share/universal-prefixes/<app>/drive_c`.

## When something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| "Close Steam first" | Steam is running. | Quit Steam fully (`steam -shutdown`), then import again. |
| "No file chooser found" | No `zenity`/`kdialog`/`yad`/`qarma`. | `sudo pacman -S zenity`, or skip the step and double-click a `.exe` — the same handler runs. |
| "Refused to write a malformed library list" | The library list on disk is not parseable (hand-edited, truncated, or written by a tool that mangled it). | Nothing was changed. Repair or replace `libraryfolders.vdf` from a backup (Steam recreates a minimal one if you delete it while Steam is closed), then retry. |
| The wizard reported the app "did not install" | The installer exited non-zero or produced no prefix. | Read `~/.local/state/continuity/wizard-install.log`, then retry with `continuity-run --installer <file>` — the wizard adds nothing you cannot do yourself. |
| "no locale list available" / "no keymap list available" | `systemd` (and so `localectl`/`timedatectl`) is not installed. | The step keeps what the machine reports and says so. Install `systemd` on a non-Arch host, or set the values by hand in `~/.config/continuity/region.conf` and `~/.config/hypr/local.conf`. |
| "NetworkManager is not installed" | No `nmcli`, so joining Wi-Fi cannot be scripted. | Connect with whatever this machine uses (it may not be NetworkManager), or `sudo pacman -S networkmanager`, then retry the step. |
| "Could not join '<ssid>'" | Wrong passphrase, or the driver refused association. | Run it by hand to see `nmcli`'s own message: `continuity-region wifi connect '<ssid>'`. |
| The import was refused | `continuity-export` found a bad checksum, a newer `SETUP_FORMAT`, or an unreadable archive — it refuses rather than half-writing. | Nothing was changed. Re-export on the source machine: `continuity-export inspect <archive>` says what the file claims to be. |
| The shakedown step shows a red chip | At least one check hard-failed (usually the 32-bit Vulkan stack or the driver). | Run `continuity-shakedown --fix` for the exact command; the detail line names the check that failed. Warnings are normal on a fresh machine. |
| It never appeared | `wizard.done` exists, or Eww was not running, or you are logged into a non-ContinuityOS session. | `continuity-wizard start`, `continuity-panel status` (is Eww running?), and see [ARCHITECTURE.md](ARCHITECTURE.md) §4. |
| "eww is not running" in the terminal | Eww is missing or crashed. | `sudo pacman -S eww`, then `continuity-panel reload` — or finish setup from the TTY, which works. |

Nothing here has been exercised on real hardware yet; treat the first run as a
shakedown and report what breaks. `tests/run.sh` covers the engine's structure and the
Steam import's happy path, duplicate no-op and malformed-file refusal.
