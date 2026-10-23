# Roadmap

Ordered by value per unit of work. Nothing here is promised; it is the list of things
worth doing next, roughly in the order they help a real user.

## Shipped recently

Four things left this list, and they change what the first hour looks like:

* **Disk installation** (`continuity-installer`, [INSTALL.md](INSTALL.md)) — the live
  medium now boots a desktop and installs to a disk through `archinstall`, then deploys
  this repository into the new system. Before it existed, `continuityos.install=1`
  configured the *live RAM* system, so there was no way to install ContinuityOS at all.
* **A no-prompt boot** (`continuity-boot`, [BOOT.md](BOOT.md)) — greetd's
  `[initial_session]` starts the session directly, so `Arch → Hyprland → ContinuityOS`
  became one step: boot, and the desktop is there. `continuity-boot off` reverses it.
* **Three more wizard steps** ([WIZARD.md](WIZARD.md)) — language/keyboard/time
  zone/Wi-Fi, an engine readiness check (`continuity-shakedown`), and moving a whole
  setup between machines (`continuity-export`), alongside the Steam/app/mode steps.
* **Setup export and import** (`continuity-export`) — prefixes, launchers, wizard
  state and preferences in one checksum-verified archive, with launcher paths rewritten
  for the receiving machine.

Each has offline coverage in `tests/run.sh`; none has been exercised on real hardware,
which is what item 1 below is still waiting for.

## Engine

1. **Test on real hardware and fix what breaks first.** The engine's logic follows
   verified umu/Proton behaviour, but no launch has been observed on a real GPU. The
   first pass should be a clean Arch install, one `.exe`, one Proton game, and a
   written list of what failed. Everything below is speculative until that exists.
2. **Per-application prefix profiles.** Let a prefix declare its own Proton build,
   `GAMEID`, MangoHud/gamescope setting and env overrides in a small `app.toml` (or
   `continuity-prefix config <slug> --proton GE-Proton`), so tuning a game does not
   mean exporting variables before a double-click.
3. **Ship the runtime offline, properly.** `continuity-umu-verify --seed` already
   supports a prebundled archive, but nothing puts one under
   `/usr/share/continuity/umu-runtimes/`. Wire that into both `iso/build.sh` (so the
   ISO can play a game before it ever reaches a network) and an opt-in
   `install.sh --bundle-runtimes`.
4. **protonfix knowledge in the UI.** umu applies protonfixes when a `GAMEID` matches.
   Add a search (`continuity-run --search-fixes <name>`) that suggests an ID instead of
   making the user read the umu database by hand.
5. **WinBoat automation.** Today `--with-winboat` installs a unit that assumes a
   `winboat` binary exists. Detect the AppImage/deb from upstream releases, install a
   launcher, and verify the container backend (Docker) is running, with a clear error
   when it is not.
6. **Wine-tricks assistance in the shell.** A drawer section that offers common
   per-prefix fixes (visual C++ runtimes, .NET, DXVK/VKD3D override) by calling the
   existing `continuity-prefix winetricks` path.
7. **Prefix health report.** `continuity-prefix doctor <slug>`: missing 32-bit libs,
   runtime validity, broken symlinks, stale `umu.lock`, wrong GPU driver for the
   reported Vulkan device.

## Shell and desktop

8. **Material You colour extraction from the wallpaper.** The Eww/Waybar palettes are
   hand-written dark palettes today; derive the accent set from the current wallpaper
   (matugen or a small script) and write the result into both stylesheets, so the
   Android resemblance survives a wallpaper change.
9. **Real gesture support.** Hyprland supports touchpad gestures; bind a three-finger
   swipe up to the quick-settings drawer and down to the notification shade so the
   shade behaves like a phone, not a menu.
10. **Notification shade polish.** Grouping, per-app icons pulled from `.desktop`
    files, swipe-to-dismiss rows, and a "clear all" that does not depend on
    `dunstctl` being the only backend.
11. **Dock polish.** Running-app indicators, magnification, and drag-to-reorder
    instead of the current fixed item list.
12. **Lock screen parity.** hyprlock currently mirrors a dark desktop; give it the
    same glass/rounding language as the drawer, plus media controls.
13. **First-boot OOBE wizard — eight steps shipped.** `continuity-wizard` runs once at
    first login: a greeting, language/keyboard/time zone/Wi-Fi, existing Steam
    libraries, moving a setup over from another machine, a first Windows program, an
    engine readiness check, and the Balanced/Gaming default (see
    [WIZARD.md](WIZARD.md)). What remains: no wallpaper picker (the three bundled assets
    are still not offered), no GE-Proton or Steam-install step, no per-step entrance
    animation — the steps appear rather than slide — and a machine-wide
    (`continuity-region … --system`) locale is still a deliberate second command rather
    than a checkbox in the step.
14. **Animation tuning pass with frame timings.** Verify the spring curves do not drop
    frames on integrated graphics, and ship a `--low-end` animation preset for laptops.

## Platform and distribution

15. **Sign the ISO, and add a version-agnostic build.** `iso/build.sh` produces an
    unsigned image whose boot-mode spellings vary by archiso version. Add a release
    workflow with checksums/signatures, and pin or detect the boot modes properly.
16. **ARM story via FEX-Emu.** Package a supported path for aarch64 that installs
    FEX-Emu, uses a *native* Wine build under it, and disables the umu/Steam-Runtime
    path with an honest explanation, rather than leaving users to discover it fails.
17. **Portability helper.** Add `distro_id()` and an `apt`/`dnf` branch to the package
    phase of `install.sh`, per [PORTING.md](PORTING.md), so the profile stops being
    Arch-only for the parts that never were.
18. **A first-class disk installer.** Today it is UEFI-only by design and *refuses*
    dual boot, LUKS and LVM rather than half-doing them. The next step is a guided
    encrypted/LVM option, a btrfs layout with snapshots, per-card hybrid-GPU advice
    (which driver the detected AMD+NVIDIA/Intel combination should get), and a
    `continuity-installer --verify-schema` preflight that proves the `archinstall` on
    the medium matches the config the installer generates *before* a disk is touched.
    [INSTALL.md](INSTALL.md) lists today's guarantees and the schema-version risk.
19. **Automated smoke tests in CI.** An Arch container that runs `install.sh --system
    --skip-packages`, checks every path it claims to install exists, runs
    `continuity-run --print-env` against a fixture `.exe`, and fails on any missing
    file — the same checks `tests/run.sh` performs locally after each change.
