# Running Freebuff on ContinuityOS

**Short answer: yes — Freebuff has a native Linux build.** There is no compatibility
layer involved, no Wine prefix, nothing to emulate. ContinuityOS also ships an
installer flag for it.

## Three routes, best first

| Route | What it is | How to get it | Why pick it |
|---|---|---|---|
| **Linux AppImage (recommended)** | Freebuff Desktop, packaged as a self-contained AppImage for **x86_64 and Arm64** | Download from <https://freebuff.com> (the site lists Linux AppImage builds for both architectures alongside the macOS and Windows downloads) | No install step, no package manager, always the version you downloaded. Runs perfectly on Arch. |
| **CLI (`freebuff-bin`, AUR)** | The terminal agent, packaged for Arch | `yay -S freebuff-bin` — or `sudo ./install.sh --system --with-freebuff` | Package-managed updates, works over SSH and in a TTY, `provides=freebuff`. Ships both `x86_64` and `aarch64` tarballs. |
| **Web** | The browser client at <https://freebuff.com> | Just open it | Works today on any machine, including one where nothing else is set up yet. |

ContinuityOS installs `--with-freebuff` support in `install.sh`:

```bash
sudo ./install.sh --system --with-freebuff
```

That tries the AUR package first (`freebuff-bin`), and if no AUR helper is available
it tells you the two remaining routes instead of failing the run.

## Integrating a downloaded AppImage with GearLever

GearLever is preinstalled by `install.sh` (Flathub `it.mijorus.gearlever`). It is the
right home for AppImages: it creates the desktop entry, extracts the icon, and can
keep older versions around.

1. Download the Freebuff AppImage from <https://freebuff.com>.
2. Make it executable and add it to GearLever:
   - **GUI:** open *Gear Lever*, drag the AppImage into the window, and confirm the
     integration.
   - **CLI:** `gearlever --integrate ~/Downloads/Freebuff-*.AppImage`
3. Freebuff now appears in the app drawer (`Super+Space`) like any packaged app.

Two things worth knowing:

- GearLever manages **AppImages**, not Flatpaks, despite both living in the same
  corner of the desktop.
- Upstream warns that running GearLever outside its Flatpak sandbox can be buggier,
  which is why `install.sh` installs the Flathub build rather than the AUR one. Keep
  it that way unless you have a reason not to.

## Where the agent actually runs

Nothing about the compatibility engine interferes with Freebuff: the AppImage is a
native Linux binary, so it runs on the host, uses the host Wayland session, and needs
no prefix. It is only in the drawer next to your Windows apps, not inside a Wine
prefix.

If you want your work in the same place your games are, note that the compatibility
engine keeps each Windows application isolated under
`~/.local/share/universal-prefixes/<slug>/drive_c/` — a path Freebuff can open and
edit like any other directory.
