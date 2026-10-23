# Compatibility matrix

What ContinuityOS can run, what it cannot, and which CachyOS package provides each
piece. UMU + Proton runs outside Steam in the Steam Linux Runtime by default; optional
direct Proton runs on host libraries, so matching 64-bit and 32-bit graphics/Vulkan
packages are essential. Windows apps are not run as root and Proton is not a kernel
feature.

## The engine

| Component | What it is | Status in ContinuityOS | Package | Notes |
|---|---|---|---|---|
| UMU + Proton | Proton outside Steam using the Steam Linux Runtime and protonfixes | **Core.** Default `continuity-run` engine (`--umu`) | `umu-launcher`, `proton-cachyos-slr` (`cachyos`) | Per-app prefix, e.g. `$CONTINUITY_PREFIX_ROOT/<slug>`; runtime is containerized by UMU. |
| Direct Proton | Host Proton script invoked without UMU | **Optional.** `continuity-run --direct` | `proton-cachyos-native` or `proton-cachyos-slr` (`cachyos`) | Uses host libraries; per-app `pfx`; less isolation/compatibility than UMU; Proton is still a user-space process. |
| GE-Proton | Community Proton build with extra media/game fixes | **Use through UMU** | `proton-ge-custom-bin` (AUR) | Valve Proton/GE builds downloaded by users can be selected with `--proton PATH`; UMU is the supported non-Steam path. |
| Wine | The Windows API implementation and explicit native fallback | **Core.** `continuity-run --native` | `wine`, `wine-mono`, `wine-gecko` (`multilib`) | Useful for utilities, `.msi` and `.lnk` files. |
| WinBoat | Runs Windows utilities inside a container and bridges their windows onto the Linux desktop | **Optional, off by default** | not packaged for Arch; install from upstream releases | Needs a container backend (Docker). Kernel-anti-cheat and driver-level software is the target use case. |
| protontricks | Winetricks for Proton prefixes; installs DLLs/runtime pieces | **Installed** | `protontricks` (**extra**) | `continuity-prefix protontricks <slug>` runs it against the right prefix. |
| winetricks | Classic prefix tweaker | **Installed** | `winetricks` (**extra**) | `continuity-prefix winetricks <slug> ...` |
| gamescope | Micro-compositor for games (resolution, HDR, upscaling) | **Installed** | `gamescope` (**extra**) | Opt in per launch with `CONTINUITY_GAMESCOPE=1`. |
| MangoHud / GameMode | Frame overlay and CPU/GPU priority | **Installed** | `mangohud`, `gamemode` | MangoHud opt in with `CONTINUITY_MANGOHUD=1`; gaming mode sets the performance power profile. |
| Steam | The storefront/client, with its own Proton and prefixes | **Supported, not wrapped** | `steam` (**multilib**) | Steam keeps `steamapps/compatdata` untouched by ContinuityOS, by design. |

### File types a double-click handles

| Extension | MIME type | Handler |
|---|---|---|
| `.exe` | `application/x-ms-dos-executable`, `application/x-msdownload`, `application/vnd.microsoft.portable-executable` | `continuity-wine.desktop` → `continuity-run` → UMU + Proton by default |
| `.msi` | `application/x-msi` | `continuity-wine.desktop` → `continuity-run` → `wine msiexec /i` |
| `.lnk` | `application/x-ms-shortcut` | `continuity-run` → `wine start /unix` |
| `.bat`, `.cmd` | shell scripts | `continuity-run` (Wine path) |

## Extras you asked for, and what actually exists

| Requested | Reality | Status |
|---|---|---|
| **GearLever** | Real: GTK4 AppImage manager (`it.mijorus.gearlever`) — it manages **AppImages**, not Flatpaks. Flathub + AUR `gearlever`. Upstream notes the Flatpak build is the well-tested one. | **Preinstalled** via Flatpak by `install.sh`. |
| **Autonomix** | Real app (`github.com/ninepointlabs/autonomix`), but it tracks/installs apps from GitHub releases (`.deb`/`.rpm`/AppImage/Flatpak/Snap). No AUR package, no current Flathub listing, and the repo was **archived 2026-01-15**. It is **not** a system-tweaking suite. | **Not preinstalled** — the request as written is not satisfiable. See substitutes below. |
| **ArtCraft** (PhotoCraft, FilmCraft, …) | Real: `getartcraft.com`, Rust, MIT/Apache-2.0. PhotoCraft is **early alpha**, FilmCraft is **in development**. Not on Flathub (site offers `.flatpak` bundles); AUR `photocraft`, `filmcraft-git`. | **Shipped as a supplement**, never as the only creative app. |
| **32-bit (multilib) gaming stack** | Required by Wine/Proton; lives in `multilib` | `install.sh` enables `[multilib]` if needed and installs `lib32-*` graphics libraries. |
| **ARM support** | Proton/umu and `lib32-*` are x86_64 artefacts | Documented honestly in [ARM.md](ARM.md); the ISO is x86_64 only. |

### If you wanted Autonomix for system maintenance

These are the real Arch tools for that job, all of which you can install today:

| Need | Tool | Package |
|---|---|---|
| Snapshots / rollback | Timeshift | `timeshift` (extra) |
| Btrfs snapshots + GUI | Snapper + Btrfs Assistant | `snapper`, `btrfs-assistant` |
| Update hygiene (news, `.pacnew`, service restarts) | Arch-Update | `arch-update` (AUR) |
| Faster mirrors | rate-mirrors | `rate-mirrors` |
| Automating anything around package transactions | pacman's own ALPM hooks — already used here | built in (`/etc/pacman.d/hooks/`) |
| Old Autonomix build (archived) | its v0.3.4 `.flatpak` bundle, from its releases page | `flatpak install --user ./io.github.plebone.autonomix-0.3.4.flatpak` |

## The mature creative stack

ArtCraft is not a replacement for these. `install.sh --system` installs them (skip
with `--gaming-only`):

| Function | Application | Package |
|---|---|---|
| Raster editing / painting | GIMP, Krita | `gimp`, `krita` (extra) |
| RAW development, photo library | darktable, digiKam | `darktable`, `digikam` (extra) |
| Vector illustration | Inkscape | `inkscape` (extra) |
| Video editing | Kdenlive | `kdenlive` (extra) |
| Audio (DAW, waveform editing) | Ardour, Audacity | `ardour`, `audacity` (extra) |
| 3D / animation / compositing | Blender | `blender` (extra) |
| Capture and streaming | OBS Studio | `obs-studio` (extra) |
| Early-alpha ArtCraft apps | PhotoCraft, FilmCraft | `photocraft`, `filmcraft-git` (AUR) |

## What cannot work

- **“Kernel-level Proton.”** Proton is a user-space Wine compatibility layer, not a kernel component. Linux cannot natively execute Windows PE binaries; Proton/Wine translate their APIs. `umu-launcher` uses a Steam Linux Runtime container (not a security sandbox); never launch untrusted Windows programs as root, and assume they can access the logged-in user's data.

- **macOS applications.** Apple's boot/hardware locks and entitlement signing mean
  there is no legitimate emulation path on non-Apple hardware. Out of scope by design.
- **Windows software with kernel-level anti-cheat** (many competitive online titles).
  It requires kernel drivers that no compatibility layer can provide; a Windows VM
  with GPU passthrough is the only real option.
- **Deep-driver Windows software**: enterprise VPNs, hardware programming tools,
  some anti-cheat launchers. Try `--native` Wine first, then WinBoat.
- **ARM hosts**, unless you add a translation layer (FEX-Emu/Box64) and accept a real
  performance cost — and note the 32-bit stack does not translate cleanly.
- **Steam's own prefixes.** ContinuityOS never writes into `steamapps/compatdata`;
  a "broken Steam game" must be fixed with Steam's own tools, not
  `continuity-prefix`, whose `rm` only touches
  `~/.local/share/universal-prefixes/<slug>/`.
