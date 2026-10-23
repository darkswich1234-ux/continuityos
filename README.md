# ContinuityOS

A gamer-friendly **Arch Linux profile**: a universal Windows compatibility engine
(`umu-run` + Proton, plus Wine and an optional WinBoat bridge) under a fluid,
Android-style Hyprland desktop — with a one-switch gaming mode that strips the
desktop back to frames.

> **What this is.** ContinuityOS is *not* a forked distribution with its own package
> repositories. It is a **profile and automation layer on top of Arch Linux**:
> packages, configs, MIME handlers, systemd units and pacman hooks applied by one
> script, `install.sh`. You can put it on an existing Arch install, or boot the live
> medium from `iso/`, which installs ContinuityOS **to a disk** and reboots straight
> into it ([docs/INSTALL.md](docs/INSTALL.md)). Everything it does is reversible by
> hand (see [docs/UNINSTALL.md](docs/UNINSTALL.md)).

---

## Install

| Mode | Command | What it does |
|---|---|---|
| Per-user | `./install.sh --user` | Everything inside `$HOME` for the current user. Safe on a working Arch box. |
| System-wide | `sudo ./install.sh --system` | Packages, the `continuity-*` CLI, `/etc` files, pacman hooks, systemd units, the Wayland session, system-wide MIME defaults. |
| Both | `sudo ./install.sh --all --yes` | `--system` then `--user` for the target user. This is what the ISO runs. |
| Preview | `./install.sh --all --dry-run` | Prints every action and changes nothing. |
| Engine only (any Linux) | `./standalone/install.sh` | Just the Windows compatibility engine — the `proton` command, isolated prefixes, the `.exe` handler — on Debian/Ubuntu, Fedora or Arch. No ISO, no desktop, no boot changes. See [docs/ENGINE-ONLY.md](docs/ENGINE-ONLY.md). |

Useful flags: `--skip-packages` (configure only), `--with-aur` (GE-Proton, Heroic,
ArtCraft, GearLever, `--with-winboat`), `--no-aur`, `--with-freebuff`, `--gaming-only`,
`--target-user NAME`, `--src DIR`, `--no-enable`, `--no-autologin` (keep a login
prompt — `--system`/`--all` configure a no-prompt boot otherwise), `-v`.

Build the install medium with `sudo iso/build.sh` (see [iso/README.md](iso/README.md)).
If you only want to run Windows programs on the Linux you already use, `./standalone/install.sh` installs the engine alone and you can ignore the rest of this file ([docs/ENGINE-ONLY.md](docs/ENGINE-ONLY.md)).

---

## What you get

**The Universal Windows Compatibility Engine.** Double-click *any* `.exe`, `.msi`,
`.bat` or `.lnk` and it launches through `continuity-run`, which gives the
application its own isolated prefix:

```
~/.local/share/universal-prefixes/<app-slug>/drive_c/
```

One slug = one directory = one `WINEPREFIX`. Proton and the Steam Linux Runtime are
bootstrapped by `umu-run`; `continuity-umu-verify` seeds and validates that runtime
tree (at login, after relevant package upgrades, and before a launch) so a
half-downloaded runtime never surfaces as a confusing validation error. See
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

**It installs itself, and then boots itself.** Boot the live medium and you land on
the ContinuityOS desktop as a live user, with one window on screen: a guided disk
install that partitions the disk, runs `archinstall` for a minimal Arch, deploys this
repository into the new system and hands it over to `install.sh`. Reboot, and the
machine comes up **in ContinuityOS** — no TTY login and no session chooser, because
greetd's `[initial_session]` starts the session itself. Details:
[docs/INSTALL.md](docs/INSTALL.md) and [docs/BOOT.md](docs/BOOT.md); undo the boot
part any time with `sudo continuity-boot off`.

**The Android-like shell.** Hyprland + Waybar "status pill" + Eww quick-settings
drawer that slides down like an Android notification shade, a bottom overlay dock,
dunst heads-up notifications, dark wallpaper palette with light icons, springs and
slide animations everywhere.

**A first-run wizard, eight steps long.** On your first login a card walks you through
setting the machine up in the order that matters: language, keyboard, time zone and
Wi-Fi; your existing Steam libraries; a setup archive from another machine, if you
have one; your first Windows program; a hardware/engine check that answers "will
games actually run here?"; and whether sessions start Balanced or Gaming. It appears
once, it is skippable, every step is also a command, and it works headless if Eww is
missing — see [docs/WIZARD.md](docs/WIZARD.md).

**Gaming mode.** `Super+G` (or the drawer's Performance switch) turns off animations,
blur, shadows and gaps, hides the bar and dock, stops notification and indexer
daemons, sets the performance power profile, and skips the runtime re-check. `off`
restores exactly the state it saved.

**Creative suite.** ArtCraft (PhotoCraft/FilmCraft, alpha-stage Rust apps) ships
*alongside* — never instead of — GIMP, Krita, Inkscape, Kdenlive, darktable,
digiKam, Blender, Ardour, Audacity and OBS Studio.

---

## Quick tour

| Command | What it does |
|---|---|
| `proton <file.exe>` | The same launcher under its standalone name: run, list, inspect and remove prefixes, and `proton check` for readiness. Installed by `standalone/install.sh`.
| `continuity-run <file.exe>` | Launch a Windows binary in its own prefix. `--installer` registers launchers afterwards, `--native` uses plain Wine, `--print-env` shows the resolved environment without launching. |
| `continuity-prefix list\|info\|scan\|launchers\|rm\|export\|import` | Inspect prefixes, register app launchers, and fully uninstall one. |
| `continuity-umu-verify --check\|--seed` | Validate or repair the Steam Linux Runtime set in `~/.local/share/umu/`. |
| `continuity-gaming-mode on\|off\|toggle\|status` | The lean gaming session. |
| `continuity-panel toggle drawer\|notifications` | Open the quick settings, the shade, or the dock; `continuity-panel power` is the power menu. `continuity-panel wizard [page]`, `region`, `shakedown`, `transfer` and `boot` jump straight to a setup step or report the boot path. |
| `continuity-screenshot region\|window\|full` | Screenshot to `~/Pictures/Screenshots`, copied to the clipboard. |
| `continuity-wizard start\|reset` | The first-run flow: locale/keyboard/Wi-Fi, Steam library import, moving a setup, first Windows app, an engine check, Balanced/Gaming default. |
| `continuity-shakedown [--probe\|--json\|--fix]` | Readiness report: Vulkan, the 32-bit stack, Wine/Proton, the Steam Linux Runtime, the GPU driver. `--probe` launches a real Windows program in a throwaway prefix. |
| `continuity-region show\|locale\|keymap\|timezone\|wifi` | Locale, keyboard layout, time zone and Wi-Fi. Per-user by default, `--system` for the whole machine. |
| `continuity-export export\|import\|inspect\|list` | Move an entire setup — Windows prefixes, their launchers, preferences — to another machine as one verified archive. |
| `continuity-boot on\|off\|status\|doctor` | What this machine does at boot: straight into the desktop, or back to a login prompt. |
| `continuity-installer ui\|disks\|plan\|install` | The guided disk install (live medium). `plan` prints the whole plan and writes the config without touching a disk. |
| `continuity-shell` | Start the session from a TTY (the login menu entry is called *ContinuityOS*). |

Keybinds: `Super+Space`/`Super+D` app drawer, `Super+W` quick settings,
`Super+N` notifications, `Super+G` gaming mode, `Super+RETURN` terminal,
`Super+L` lock, `PRINT` screenshot.

---

## Your first hour (coming from Windows)

1. **Boot the medium and install.** Boot `iso/`'s image in **UEFI** mode; you land on
   the ContinuityOS desktop and the installer window asks which disk to erase, then
   runs the same `install.sh --all --yes` this repository has always used
   ([docs/INSTALL.md](docs/INSTALL.md)). Unattended: add
   `continuityos.install=1 continuityos.disk=/dev/nvme0n1` to the kernel command line.
   Already running Arch? Skip this step and use `sudo ./install.sh --all --yes`.
2. **Reboot — it comes up by itself, then set it up.** No login prompt and no session
   chooser: greetd starts the session directly, and the choice is recorded in
   `/etc/continuity/install.conf` (`sudo continuity-boot off` restores a login prompt;
   a logout shows a normal greeter, which is the way back in if the desktop ever
   breaks — [docs/BOOT.md](docs/BOOT.md)). A couple of seconds after the shell appears
   the wizard greets you: eight skippable steps covering language/keyboard/zone/Wi-Fi,
   your Steam libraries, a setup archive from another machine, a first Windows
   program, an engine check, and the Balanced/Gaming default. If Steam is open it will
   refuse to edit the library list until you close it ([docs/WIZARD.md](docs/WIZARD.md)).
3. **Check the engine.** Run `continuity-umu-verify --check`. On a fresh machine it
   reports `steamrt3` as not installed yet — that is expected: the first game launch
   downloads the runtime once (needs internet). If you have a prebundled archive in
   `/usr/share/continuity/umu-runtimes/`, `--seed` installs it offline.
4. **Bring your Steam library over.** Install Steam, add the same library folder, and
   install GE-Proton with `yay -S proton-ge-custom-bin`. Steam manages its own
   prefixes under `steamapps/compatdata` — ContinuityOS deliberately never touches
   those. Use `continuity-run` for the things Steam cannot install: GOG/itch
   installers, patchers, standalone mod tools, utility `.exe`s.
5. **Install something.** Double-click `GameSetup.exe`. It runs in a brand-new prefix;
   watch it appear in `continuity-prefix list`. Or be explicit:

   ```bash
   continuity-run --installer --name MyGame ~/Downloads/GameSetup.exe
   continuity-prefix launchers mygame --auto     # desktop entries for what it installed
   continuity-prefix info mygame                 # size, executables, launchers
   ```

6. **Why a prefix is nice.** A game that corrupts its Wine install only ruins its own
   directory. Removing it is one command and leaves no registry or DLL residue:

   ```bash
   continuity-prefix rm mygame        # removes the prefix AND its launchers
   ```

   Back it up first if you care: `continuity-prefix export mygame mygame.tar.zst`.
7. **Utilities Proton cannot run.** If a corporate/enterprise app misbehaves under
   Proton, try `continuity-run --native`, and if that fails too, install the WinBoat
   container bridge: `sudo ./install.sh --system --with-winboat`.
8. **Gentle on the hardware.** `Super+G` before you play; `continuity-gaming-mode
   status --json` if you want to script it.
9. **Your agent.** Freebuff has a native Linux build — see [docs/FREEBUFF.md](docs/FREEBUFF.md),
   or install it with `sudo ./install.sh --system --with-freebuff`.

---

## Optional private desktop prototype

A separate, pinned scaffold is available for privately testing pctrade's end4-pC Quickshell overlay. It is not installed or bundled into the ISO, and it does not replace ContinuityOS's shell or Proton/UMU defaults. Start with [docs/END4-PC.md](docs/END4-PC.md); after installing the illogical-impulse prerequisite and reviewing its changes, `continuity-end4-pc install` stages the exact reviewed overlay commit and `continuity-end4-pc launch` tests it without modifying Hyprland autostart.

## Directory map

```
install.sh                 unified installer (--user | --system | --all)
bin/                       the continuity-* CLI, installed to /usr/local/bin
lib/continuity-common.sh   shared paths/logging/slug helpers (installed to /usr/local/lib/continuity)
config/hypr/               Hyprland session, animations, keybinds, wallpaper, lock/idle
config/waybar/             the top status pill
config/eww/                dock, quick-settings drawer, notification shade (+ scripts/)
config/rofi/               app-drawer theme
config/continuity/         default environment.conf (engine tuning)
config/greetd/             the template that makes boot go straight to the desktop
                           (rendered to /etc/greetd/config.toml by continuity-boot)
desktop/                   .desktop entries + the .exe MIME associations
sessions/                  the Wayland session file for the login manager
systemd/                   user + system units (runtime seeding, first boot, WinBoat)
pacman/hooks/              ALPM hooks (runtime re-check, desktop/mime database refresh)
packages/*.list            package sets: core, desktop, gaming, creative, aur
                           (the graphics stack is chosen by GPU detection inside install.sh,
                            not from a fixed list)
assets/wallpapers/         dark wallpaper source (converted to PNG on install)
assets/icons/              the light-on-dark icons the repo references
standalone/                engine-only installer for an existing Linux (no ISO, no desktop)
iso/                       archiso profile + builder for a live/installable image
docs/                      architecture, boot + disk install (BOOT.md, INSTALL.md),
                           wizard, compatibility, uninstall, porting, roadmap
  END4-PC.md                optional pinned private end4-pC overlay + VM/GDB notes
```

Architecture and internal contract (env vars, prefix layout, CLI guarantees):
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## What is real vs. aspirational

Honest inventory, because you are about to depend on this:

- **The disk installer and the autologin are new and unproven.** No ISO has been
  built and booted here, no disk has been erased, `archinstall` has never been
  invoked and `continuity-boot` has never started a real greetd. Their logic,
  refusals and the files they generate are covered offline by `tests/run.sh`, which
  is the limit of what a machine without a spare disk can prove. Install to a disk you
  can lose, and keep a second VT in mind while you do it.
- **The engine, the shell and the installer are real code, but untested on your
  hardware.** The parts that talk to Arch (`pacman`, package names, `umu-launcher`
  in `multilib`, `pv-verify` runtime checks) are written against verified package and
  upstream behaviour; the visual side (Hyprland/Waybar/Eww) still needs a session on
  your actual GPU to be called polished. Treat the first boot as a shakedown, and
  run `./install.sh --all --dry-run` first.
- **Autonomix could not be delivered as requested.** It exists, but it is a
  GitHub-release app updater (not a system tweaking tool), it has no AUR package and
  no current Flathub listing, and its repository was archived on 2026-01-15. It is
  therefore **not** preinstalled. The real Arch alternatives for what you probably
  wanted (system maintenance, snapshots, update hygiene) are listed in
  [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).
- **GearLever is preinstalled** (Flathub `it.mijorus.gearlever`) and is the right
  home for AppImages such as Freebuff's. It manages AppImages — confusingly, not
  Flatpaks. Upstream warns the non-Flatpak build is buggier, which is why the
  installer uses the Flatpak.
- **ArtCraft is real but early.** PhotoCraft is labelled early alpha and FilmCraft is
  in development. Do not build a paid workflow on them yet; the mature FOSS stack
  above is what should carry you.
- **WinBoat is optional and needs Docker.** Proton cannot run kernel-anti-cheat or
  deep-driver Windows software; a container/VM bridge is the only honest answer.
- **ARM is not covered by the ISO.** Proton, `umu-run` and the 32-bit graphics stack
  are x86_64 artefacts; see [docs/ARM.md](docs/ARM.md).
- **macOS binaries are out of scope by design** — Apple's hardware and entitlement
  locks mean there is no legitimate path, so the engine targets Windows only.

Roadmap and next steps: [docs/ROADMAP.md](docs/ROADMAP.md).
