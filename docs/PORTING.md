# Porting ContinuityOS off Arch

ContinuityOS is written *for Arch*, but almost none of it depends on Arch
specifically. Here is what is Arch-shaped and what you would need to change.

## What is actually Arch-specific

| Area | Where | Why it is Arch-specific |
|---|---|---|
| Package installation | `install.sh` → `install_packages_system`, `install_aur`, `enable_multilib`, and `packages/*.list` | `pacman -S --needed`, the `[multilib]` repo, and an AUR helper (`yay`) for GE-Proton/ArtCraft/Freebuff. |
| ALPM hooks | `pacman/hooks/*.hook` | They use pacman's `[Trigger]`/`[Action]` hook format. Debian/Fedora have no equivalent drop-in; you need a dpkg/native trigger or a timer. |
| Package names | `packages/*.list` | `lib32-*`, `vulkan-radeon`, `hyprland-qtutils`, `ttf-jetbrains-mono-nerd` etc. are Arch naming. Every other distro renames at least some. |
| Kernel recommendation | `iso/profile/packages.x86_64`, docs | `linux-zen` is an Arch kernel package; other distros have their own low-latency kernels (e.g. `linux-lowlatency`, `kernel-xanmod`). |
| The ISO | `iso/` | archiso is Arch-only. |
| Service wiring | `systemd/*` | Nothing Debian/Fedora-specific, but you will install them to different destinations if you use a non-systemd distro (everything breaks on such a distro). |

## What is portable as-is

- **The whole CLI** (`bin/*`, `lib/continuity-common.sh`). It uses only bash coreutils,
  `xdg-*`, `pgrep`, and optional helpers that are detected at runtime.
- **`continuity-umu-verify`**, as long as `umu-launcher` is installed and its runtime
  root is `~/.local/share/umu/` (it honours `CONTINUITY_UMU_ROOT`). umu-launcher itself
  is distributed as a Python package and a Flatpak, so it exists beyond Arch.
- **All config trees** (`config/hypr`, `config/waybar`, `config/eww`, `config/rofi`,
  `config/dunst`) — these are upstream-tool configs, not distribution configs.
- **`continuity-prefix`, `continuity-gaming-mode`, `continuity-panel`,
  `continuity-screenshot`, `continuity-shell`, `continuity-session-start`** — no
  packaging system involved.
- **The prefix layout** (`~/.local/share/universal-prefixes/<slug>/drive_c/`) and the
  MIME story (`application/x-ms-dos-executable` → a `.desktop` file), which is
  freedesktop standard and works on any XDG-compliant desktop.

## A concrete port

1. **Map the package lists.** Create a parallel list file per distro, e.g.
   `packages/debian.list`, and note the renames you hit. The usual ones:

   | Arch | Debian/Ubuntu | Fedora |
   |---|---|---|
   | `lib32-mesa`, `lib32-vulkan-icd-loader` | `mesa-vulkan-drivers:i386`, `libgl1-mesa-dri:i386` | `mesa-vulkan-drivers.i686`, `glibc.i686` |
   | `vulkan-radeon` | `mesa-vulkan-drivers` | `mesa-vulkan-drivers` |
   | `hyprland`, `waybar`, `eww` | Hyprland is in Debian 13+/Ubuntu 24.10+; `waybar`, `eww` in newer repos | Hyprland/Waybar packaged; `eww` via COPR or build from source |
   | `steam` | `steam` (needs `i386` arch enabled) | `steam` (RPM Fusion) |
   | `umu-launcher` | pipx/`umu-launcher` or Flatpak `info.umu-launcher.umu` | same |
   | i386/multilib enablement | `dpkg --add-architecture i386 && apt update` | `dnf install ...i686` |
   | AUR equivalent for GE-Proton | `protonup-qt`, manual `compatibilitytools.d` download | `protonup-qt` |

2. **Replace the package phase.** Add a `distro_id()` helper in `install.sh` and branch:
   `pacman` (current), `apt`, `dnf`. Keep every phase after the package phase
   unchanged — the config, MIME, unit and hook work is package-manager agnostic.
3. **Replace the ALPM hooks with a timer.** On non-Arch systems, ship a
   `continuity-umu-verify.timer` (the unit already exists in `systemd/`) as the
   substitute for `pacman/hooks/99-continuity-umu.hook`, and add a dpkg/native trigger
   only if you want post-upgrade immediacy.
4. **Rename nothing else.** `continuity-*` paths, `~/.config/continuity/` and
   `~/.local/share/universal-prefixes/` stay the same, so the documentation here
   remains valid.
5. **Drop the ISO, or write a new one.** archiso does not port; on Debian you would use
   `live-build`, on Fedora `lorax`/`kiwi`. `iso/README.md` describes what the live
   medium must contain, which maps to any of those builders.

## Things that will bite you

- **32-bit graphics on a pure-`amd64` distro** is the single biggest porting hazard:
  no `lib32` packages, no Proton. Verify `lib32-vulkan-icd-loader`'s equivalent is
  installed before blaming the engine.
- **`umu-launcher` outside the repos** needs its Python dependency chain; the Flatpak
  build is the least painful path, at the cost of prefix paths being host-resolved.
- **Hyprland versions** differ enough that the `windowrule`/`animation` grammar in
  `config/hypr/conf.d/` may need adjusting to the version your distro ships — see
  [HYPRLAND-LUA-MIGRATION.md](HYPRLAND-LUA-MIGRATION.md).
- **Non-systemd distros** (Void, Gentoo/OpenRC, Alpine, Artix) have no `systemctl`:
  everything still runs because the shell scripts degrade to no-ops, but runtime
  seeding and first boot must move to your init's equivalent.
