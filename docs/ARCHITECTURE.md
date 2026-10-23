# ContinuityOS — Architecture & Internal Contract

> This file is the **contract**. Every script and config in this repo conforms to the paths,
> variable names and CLI signatures defined here. If you change something here, change the
> code that reads it (and vice-versa).

ContinuityOS is not a forked distro with its own package repos. It is a **profile + automation
layer on top of Arch Linux** that can be applied in two ways:

| Mode | Command | What it does |
|---|---|---|
| Per-user profile | `./install.sh --user` | Installs/configures everything inside `$HOME` for the current user. Safe on an existing Arch install. |
| System-wide (distro) | `sudo ./install.sh --system` | Installs packages, `/etc` files, pacman hooks, systemd units, session files. |
| Both (fresh machine / ISO) | `sudo ./install.sh --all --yes` | `--system` then `--user` for the invoking/target user. |

---

## 1. Filesystem contract

### Runtime (per-user)

| Purpose | Path | Variable |
|---|---|---|
| Config root | `~/.config/continuity/` | `CONTINUITY_CONFIG_DIR` |
| Main env file (sourced by all tools) | `~/.config/continuity/environment.conf` | — |
| Region (locale, time zone) | `~/.config/continuity/region.conf` (sourced by `continuity-shell`) | — |
| ↳ the same values for `systemd --user` | `~/.config/environment.d/10-continuity-region.conf` | — |
| Keyboard layout block | `~/.config/hypr/local.conf` (one fenced `input { kb_layout = … }`) | — |
| Displaced files from an import | `~/.local/state/continuity/replaced/` | — |
| **Wine prefixes** | `~/.local/share/universal-prefixes/<slug>/` | `CONTINUITY_PREFIX_ROOT` |
| ↳ `drive_c` inside prefix | `~/.local/share/universal-prefixes/<slug>/drive_c/` | — |
| Proton installs | Steam library `steamapps/common/Proton*` and `compatibilitytools.d/` | `CONTINUITY_PROTONPATH` overrides selection |
| Steam install root | `~/.local/share/Steam/` (detected; may be overridden) | `CONTINUITY_STEAM_ROOT` |
| Generated launchers | `~/.local/share/applications/continuity/<slug>/` | `CONTINUITY_LAUNCHER_DIR` |
| Logs / runtime state | `~/.local/state/continuity/` | `CONTINUITY_STATE_DIR` |
| Assets (wallpapers, icons) | `~/.local/share/continuity/assets/` | — |

`XDG_DATA_HOME` / `XDG_CONFIG_HOME` / `XDG_STATE_HOME` are always honoured if set.

### System

| Purpose | Path |
|---|---|
| CLI tools | `/usr/local/bin/continuity-*` |
| Desktop entries | `/usr/share/applications/continuity-*.desktop` |
| MIME defaults | `/usr/share/applications/mimeapps.list` (user: `~/.config/mimeapps.list`) |
| Pacman hooks | `/etc/pacman.d/hooks/*-continuity*.hook` |
| Systemd system units | `/etc/systemd/system/continuity-*.{service,timer}` |
| Systemd user units | `/usr/lib/systemd/user/continuity-*.{service,timer}` |
| Login manager config | `/etc/greetd/config.toml` (rendered by `continuity-boot` from `config/greetd/config.toml.tmpl`, which `install.sh` also copies to `/usr/share/continuity/config/greetd/`) |
| Login manager unit | `greetd.service` (owned by the `greetd` package; it carries `Conflicts=getty@tty1.service` and `Alias=display-manager.service`) |
| Install state | `/etc/continuity/install.conf` (`CONTINUITY_AUTOLOGIN` records the boot choice) |
| Hyprland session | `/usr/share/wayland-sessions/continuity.desktop` |

---

## 2. Prefix naming (`slug`)

A prefix slug is derived from an application name:

```
My Game: Definitive Edition!  ->  my-game-definitive-edition
setup.exe                     ->  setup
```

Rules (implemented once, in `bin/continuity-run` → `continuity_slugify`):
lowercase, `[^a-z0-9]+` collapsed to `-`, leading/trailing `-` stripped, truncated to 64 chars,
empty result falls back to `windows-app`.

Slug `default` is reserved for `.exe` files double-clicked with no discernible app name.

---

## 3. The Windows Compatibility Engine

### 3.1 Launch path

```
double-click foo.exe
  -> desktop entry continuity-wine.desktop
     Exec=/usr/local/bin/continuity-run %f
  -> continuity-run derives slug, ensures compatdata/<slug>/
  -> Proton's `proton waitforexitandrun` script runs directly on the host
  -> Proton uses compatdata/<slug>/pfx as this app's isolated Wine prefix
```

Layers, innermost first:

1. **Valve Proton** — the default engine. `continuity-run` locates a Steam-installed Proton
   build and calls its `proton waitforexitandrun <exe>` entry point directly on the host.
2. **Wine** (`wine` / `wine-staging`, `multilib`) — explicit fallback (`--native`), and the
   required helper for `.msi` installers and `.lnk` shortcuts.
3. **WinBoat** (container-based Windows VM/app bridge) — the escape hatch for enterprise
   utilities that neither Proton nor Wine can run. Optional: `install.sh --with-winboat`.

### 3.2 Environment passed to Proton

Each app has independent compatdata at `$CONTINUITY_PREFIX_ROOT/<slug>/`; Valve Proton
creates its Wine prefix at `<compatdata>/pfx/`. `continuity-run` also migrates legacy
ContinuityOS `<slug>/drive_c` prefixes into that `pfx/` directory without deleting files.

| Variable | ContinuityOS value |
|---|---|
| `STEAM_COMPAT_DATA_PATH` | `$CONTINUITY_PREFIX_ROOT/<slug>` |
| `WINEPREFIX` | `$CONTINUITY_PREFIX_ROOT/<slug>/pfx` |
| `STEAM_COMPAT_CLIENT_INSTALL_PATH` | detected Steam root, or `CONTINUITY_STEAM_ROOT` |
| `STEAM_COMPAT_APP_ID`, `SteamAppId`, `SteamGameId` | `--game`/`CONTINUITY_GAMEID` (default `0`) |
| Proton verb | `waitforexitandrun` (default) |

This is **direct host execution**, not UMU and not pressure-vessel: Proton's dependencies,
including host graphics drivers and 32-bit Vulkan libraries, resolve against the host. This
is intentionally less portable than Steam's runtime container. `.msi` and `.lnk` inputs are
routed to Wine because their shell helper verbs are not ordinary Proton executable launches.

**Upstream support caveat:** GE-Proton explicitly supports non-Steam games outside Steam only
through UMU. ContinuityOS's direct host path defaults to Valve's Steam Proton; explicitly
selecting GE-Proton or other unofficial builds is unsupported by their upstream maintainers.
Use them at your own risk. UMU/runtime seeding is not part of the launch contract.

**Critically:** desktop `Exec=` lines do **not** run through a shell. Never put `~`, `$HOME`
or `$XDG_*` in a `.desktop` file — all expansion happens inside `continuity-run`.


### 3.3 Prefix isolation guarantee

One slug = one directory = one `WINEPREFIX`. Nothing writes into another prefix, and
`continuity-prefix rm <slug>` is a complete, verifiable uninstall: it removes exactly one
directory tree. Prefixes are never shared with Steam (`~/.steam/steam/steamapps/compatdata`)
so a broken game cannot corrupt your Steam library config.

---

## 4. Desktop shell (Android-like)

| Piece | Implementation | Config |
|---|---|---|
| Compositor | Hyprland (`hyprland` + `hyprland-qtutils`) | `config/hypr/` |
| Status bar / pill | Waybar (top "status pill") | `config/waybar/` |
| Quick-settings drawer + notification shade | **Eww** (GTK layer-shell windows) | `config/eww/` |
| Dock | Eww bottom dock (`dock` window) | `config/eww/` |
| Wallpaper | `hyprpaper`, dark gradient pack | `config/hypr/hyprpaper.conf`, `assets/wallpapers/` |
| Notifications | `dunst` (styled as Android heads-up) | `config/dunst/` |
| Launcher | `rofi -show drun` themed as an app-drawer, or Eww search | `config/rofi/` |
| Idle/lock | `hypridle` + `hyprlock` | `config/hypr/` |
| First-run wizard | **Eww**, one window per step (eight), driven by `bin/continuity-wizard`, which delegates the heavy work to `continuity-region` / `continuity-shakedown` / `continuity-export` | `config/eww/`, `config/eww/scripts/wizard.sh` |
| Optional external shell prototype | end4-pC (pctrade's illogical-impulse Quickshell overlay), user-installed and manually launched; not part of the default session or ISO | `bin/continuity-end4-pc`, [END4-PC.md](END4-PC.md) |

Shell entrypoints that other components are allowed to call (stable interface):

```
continuity-shell          # start the session (hyprland with ContinuityOS env)
continuity-panel toggle   # open/close the quick-settings drawer (Eww)
continuity-panel notifications
continuity-gaming-mode on|off|toggle|status
continuity-wizard start|show-once|get <key>   # first-run flow (see 4.1)
continuity-boot on|off|status|doctor          # the boot path (see 4.2)
continuity-region show|locale|keymap|timezone|wifi
continuity-shakedown [--json|--quiet|--fix|--probe|--prune]
continuity-export export|import|inspect|list
continuity-installer ui|disks|plan|install    # disk install (live medium; see INSTALL.md)
continuity-panel wizard [page]                # reopen the flow at a step
```

### 4.1 First-run wizard state contract

`bin/continuity-wizard` is the engine and the whole brain; the Eww windows are a view
of it. The window names are contract, because the engine opens them by name
(`show_page`):

| Step | Window |
|---|---|
| welcome | `wizard` |
| region | `wizard-region` |
| steam | `wizard-steam` |
| transfer | `wizard-transfer` |
| windows | `wizard-windows` |
| shakedown | `wizard-shakedown` |
| mode | `wizard-mode` |
| done | `wizard-done` |

The step order is the `PAGES` array in `bin/continuity-wizard`
(`welcome region steam transfer windows shakedown mode done`); `goto`, `next` and
`back` all index into it, so adding a step means adding the page, its window name and
its row to the view's poll set — nothing else. `show_page` refreshes a step's live
reading (`region`, `shakedown`) on *entry* rather than on every poll, because the Eww
labels read stored state and a poll must never shell out to a hardware check.

One window per step rather than one window with conditional content: Eww's `:visible`
is a relatively recent addition, and a construct the installed Eww cannot parse would
take the dock and the drawer down with it. Only one surface is ever open, so the split
costs nothing. Hyprland blurs them via `layerrule = blur on, match:namespace ^wizard`.

State lives in `~/.local/state/continuity/wizard.state` (`KEY=VALUE`, mode 0600), and
completion is the marker
`~/.local/state/continuity/wizard.done` — `show-once` is a no-op once it exists, which
is what makes it safe to call on every single login. `continuity-wizard get
GREETING|PREFIX_ROOT` computes those two values rather than storing them.

The stored keys, grouped as the tools keep them: page (`PAGE`), outcome (`MODE`,
`ERROR`), Steam (`STEAM_LIBRARY`, `STEAM_SUMMARY`, `STEAM_GAMES`,
`STEAM_CANDIDATES`), app (`APP_NAME`, `APP_STATE`, `APP_PATH`), region
(`REGION_LOCALE`, `REGION_KEYMAP`, `REGION_TIMEZONE`, `REGION_WIFI`,
`REGION_SUMMARY`), engine check (`SHAKEDOWN_STATE`, `SHAKEDOWN_SUMMARY`,
`SHAKEDOWN_HEADLINE`, `SHAKEDOWN_FIX`, `SHAKEDOWN_FAIL`, `SHAKEDOWN_WARN`) and
transfer (`TRANSFER_STATE`, `TRANSFER_ARCHIVE`, `TRANSFER_SUMMARY`). Three steps
delegate their work to separate tools — `continuity-region`, `continuity-shakedown`,
`continuity-export` — and the wizard stores only what the card displays.

The engine must keep working with no Eww installed: it degrades to printed guidance per
page, because a first-run flow that cannot be completed is worse than none. Verification:
`tests/run.sh` checks the window names structurally and exercises the Steam import's
happy path, its duplicate no-op and its malformed-file refusal. `docs/WIZARD.md` is the
user-facing counterpart.

### 4.2 Boot chain (no login prompt, no session chooser)

A stock Arch install stops twice on the way to a desktop — a TTY login, then a
session chooser. ContinuityOS removes both by making the session the login manager's
`[initial_session]`:

```
greetd ──▶ [initial_session] /usr/local/bin/continuity-shell  (user: the account)
   └────▶ [default_session] tuigreet                             (only after a logout)
```

| Piece | Owns |
|---|---|
| `config/greetd/config.toml.tmpl` | the canonical file: `[terminal]`, `[default_session]`, and one autologin block fenced by `# >>> continuity-autologin` markers |
| `bin/continuity-boot on\|off` | renders that template to `/etc/greetd/config.toml`, enables/disables `greetd.service`, and strips the fenced block for `off` |
| `install.sh` | decides the default (`on` for `--system`/`--all`, `--no-autologin` keeps a prompt, `--no-enable` leaves the boot path alone) and runs `continuity-boot` **last**, so the session binary and the target's config tree already exist |
| `tests/run.sh` | drives the whole thing against a fixture unit directory plus stub `systemctl`/`getent`, including every refusal |

`on` refuses before writing anything when the session binary is missing, the account
does not exist, the account is `root`, or another display manager is enabled — a
broken autologin is the one mistake that cannot be fixed from the desktop you cannot
reach. It never masks `getty@tty1`: greetd's own unit already conflicts with it, and
tty2 onwards stay available. `off` re-enables `getty@tty1` and leaves
`/etc/greetd/config.toml` in place (without the autologin block) so a later `on` is a
render, not a reinstall. `tools/uninstall.sh` runs `continuity-boot off` *before*
removing the session binary, because an autologin pointing at a deleted file is a
login loop.

On the live medium the same mechanism is used with the `continuity` live account
(declared in `iso/profile/airootfs/etc/sysusers.d/continuity-live.conf`), configured
by `iso/profile/airootfs/root/.automated_script.sh` after it has provisioned the live
root, and ordered *after* that hook by
`iso/profile/airootfs/etc/systemd/system/greetd.service.d/10-continuity-live.conf` —
`[initial_session]` points at a binary the hook installs. The live session opens
`continuity-installer ui` instead of the wizard: `continuity-session-start` branches
on `/run/archiso` and reads `/run/continuity-installer.mode` (`guided`|`unattended`).
Full user-facing write-ups: [BOOT.md](BOOT.md) and [INSTALL.md](INSTALL.md).

---

## 5. Gaming mode

`continuity-gaming-mode on` (also bound to `Super+G` and the drawer's Performance slider):

* `hyprctl keyword animations:enabled 0`, disables blur/shadows/rounding (GPU + CPU headroom)
* hides Waybar and the Eww dock/drawer, stops `dunst`
* `hyprctl keyword misc:disable_autoreload 1`
* stops background indexers (`baloo`-equivalents, `tracker`, `plasma` file index)
* sets CPU governor to `performance` (falls back silently when unavailable/power-profiles-daemon)
* exports `gamemode`/`MangoHud` for subsequently launched games

`off` restores the saved pre-gaming state from `$CONTINUITY_STATE_DIR/gaming-mode.state`.
Gaming mode is *state*, not a separate config file — `config/hypr/conf.d/gaming.conf` holds
only the look-and-feel deltas.

---

## 6. Creative suite

`ArtCraft` (PhotoCraft, FilmCraft, VectorCraft, LightCraft, DesignCraft, EffectCraft, PdfCraft)
is a real, MIT/Apache-2.0 FOSS suite written in Rust. **It is early alpha / in development**,
so ContinuityOS ships it *alongside* — never instead of — the mature fallbacks
(GIMP, Krita, Inkscape, Kdenlive, darktable, Blender, Ardour, OBS). See
`docs/COMPATIBILITY.md` for the honest maturity matrix.

---

## 7. Verification contract

Every script in `bin/` must:

1. be executable, POSIX-ish bash (`#!/usr/bin/env bash` + `set -euo pipefail`),
2. support `--help`,
3. print machine-parseable output where useful (`continuity-prefix list` → one slug per line),
4. never require a shell for `.desktop` invocation (no `~`, no unquoted `$VARS` in `Exec=`),
5. degrade gracefully when a helper (`hyprctl`, `flatpak`, `gamemoderun`) is missing,
6. publish a machine-readable twin where another program depends on the answer
   (`continuity-shakedown --json`, `continuity-boot status --json`,
   `continuity-region show --json`, `continuity-export inspect`), with exit codes a
   caller can trust: `0` success, `1` a real failure, `2` a usage error — and
   `continuity-shakedown` additionally reports `1` for a failed check while still
   printing the whole report,
7. never require root unless the action is genuinely machine-wide (`--system`).

Offline verification suite: `tests/run.sh` (runs `bash -n`, dry-runs `install.sh`,
exercises `continuity-run --print-env` on a real `.exe` fixture, exports and imports a
fixture setup, renders the greetd config against stubs, and generates an installer
plan against a fixture `/sys/block` tree).
