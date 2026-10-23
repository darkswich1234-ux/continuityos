# ContinuityOS icon set

**Four icons ship in this directory** — they are small, hand-drawn, and part of
the repo, not generated at install time:

| File | Referenced by | Purpose |
|---|---|---|
| `windows-app.svg` | `bin/continuity-prefix` (`write_launcher`, fallback when no `.exe` icon can be extracted) | Generic Windows application |
| `continuity-windows.svg` | `desktop/continuity-wine.desktop`, `sessions/continuity.desktop`, generated launchers | The Universal Compatibility Engine / "run an .exe" action |
| `input-gaming.svg` | `desktop/continuity-gaming-mode.desktop`, `bin/continuity-gaming-mode` notifications | Gaming mode toggle |
| `video-display.svg` | `desktop/continuity-verify.desktop`, gaming-mode restore notification | Diagnostics / leaving gaming mode |

Do not rename them without grepping the repo: `bin/continuity-prefix` writes
`Icon=$HOME/.local/share/continuity/assets/icons/windows-app.svg` literally, and
`tests/run.sh` asserts all four names exist.

## How they reach a desktop

1. `install.sh --user` copies every `*.svg` here into
   `~/.local/share/continuity/assets/icons/`.
2. `install.sh --system` copies `config/` into `/usr/share/continuity/config/`,
   and the icons are reachable through `$CONTINUITY_ASSET_DIR`.
3. Launcher desktop files written by `continuity-prefix launchers --auto` point
   at the absolute path under `$HOME`, so they resolve without an icon-theme
   lookup — which matters because a user-side entry may be the only copy on the
   system.

Paths resolve through `$CONTINUITY_ASSET_DIR` (default
`~/.local/share/continuity/assets`), so overriding an icon is a matter of
dropping a file with the same name into that directory's `icons/` folder.

## Conventions

* **Light glyphs on a dark plate.** The wallpapers
  (`assets/wallpapers/continuity-dark-0*.svg`) are dark, so each icon draws a
  translucent dark backing plate with a light glyph on top. That keeps them
  legible over both `#101014` surfaces and mid-dark wallpaper regions.
* **Palette.** `#a8c7fa` (primary/accent), `#e6e1e5` (on-surface, the glyph
  colour), `#101014` (surface), `#1b1b20` (surface-container), `#43474e`
  (outline), `#ffb4ab` (error). These are the same values used by
  `config/waybar/style.css`, `config/eww/eww.scss` and
  `config/continuity/gtk.css`.
* **256×256 viewBox, standalone SVG.** No `<text>`, no external references, no
  embedded rasters, no filters beyond a simple blur. Waybar, Eww and rofi all
  render SVG natively.
* **Bold silhouettes.** A 24 px status-pill icon needs to survive being glanced
  at, not examined: keep strokes at 1.5 px or heavier.

## The rest of the desktop's icons

ContinuityOS does not fork a whole icon theme. It inherits
`papirus-icon-theme` (with `adwaita-icon-theme` as the fallback) for everything
else, which is why `config/gtk-3.0/settings.ini` and `config/gtk-4.0/settings.ini`
set `gtk-icon-theme-name=Papirus-Dark`. Papirus is GPL-3.0-or-later; the four
icons here are original ContinuityOS artwork released as CC0-1.0 (see
`assets/README.md`), so they carry no upstream licence obligations.
