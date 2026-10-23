# ARM: what works, what does not

ContinuityOS's compatibility engine is built from x86_64 artefacts. This page states
plainly what that means, so nobody spends an evening wondering why a game will not
launch on a Snapdragon laptop.

## The facts

| Piece | Architecture reality |
|---|---|
| `umu-run` / `umu-launcher` | Packages the **x86_64** Steam Linux Runtime and runs x86_64 Proton builds. There is no ARM build of the runtime. |
| Proton / GE-Proton | x86_64 Windows binaries executed through `wine`'s WoW64. No ARM target. |
| The 32-bit graphics stack | `lib32-mesa`, `lib32-vulkan-*`, `lib32-vulkan-icd-loader` are x86_64 packages from `multilib`. On ARM (aarch64) this stack simply does not exist in that form. |
| Hyprland + the shell | **Fine.** The desktop, the drawer, the dock and gaming mode are architecture-independent. |
| Freebuff | Has a native **Arm64 Linux AppImage** — see [FREEBUFF.md](FREEBUFF.md). |
| The ISO in `iso/` | x86_64 only (`packages.x86_64`, `mkarchiso` x86_64 profile). Do not expect it to boot on ARM. |

## What you can do on ARM anyway

1. **Install the profile by hand on Arch Linux ARM**: `./install.sh --user` plus the
   shell packages. You get the desktop, the app drawer, GearLever, Freebuff and the
   creative suite.
2. **Windows binaries through a translation layer.** Install FEX-Emu (or Box64) and
   run a *native* Wine build under it. Expect a significant performance cost,
   imperfect 32-bit support, and frequent game-specific breakage. This is a hobbyist
   configuration, not a supported one — passing an x86_64 Proton build through umu
   will not work, because the Steam Linux Runtime it bootstraps is x86_64 and cannot
   execute on an ARM CPU.
3. **Stream instead of translating.** If the goal is playing your library, a remote
   play / game-streaming client uses far less of your evening than fighting a
   translation layer.

## What ContinuityOS does when it detects a non-x86_64 host

`install.sh` refuses to pretend. During preflight it prints:

```
!! host architecture is aarch64: Proton/umu need x86_64 (FEX-Emu/Box64 on ARM — see docs/ARM.md)
```

and the graphics phase skips the 32-bit Vulkan packages rather than installing a
half-working stack. The shell still installs normally.
