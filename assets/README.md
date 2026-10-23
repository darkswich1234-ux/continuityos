# ContinuityOS assets

Visual assets for the ContinuityOS desktop shell. Everything here is installed by
`install.sh --user` into `$CONTINUITY_ASSET_DIR`
(`~/.local/share/continuity/assets`) and referenced from `config/hypr`,
`config/waybar` and `config/eww`.

## Inventory

| Path | What it is | Installed to |
|---|---|---|
| `wallpapers/continuity-dark-01.svg` | "Deep Field" — deep-space gradient, nebula, starfield | `assets/wallpapers/` |
| `wallpapers/continuity-dark-02.svg` | "Aurora Drift" — diagonal aurora ribbons | `assets/wallpapers/` |
| `wallpapers/continuity-dark-03.svg` | "Facet" — translucent geometry over a fine grid | `assets/wallpapers/` |
| `icons/` | Icon **contract** only — see `icons/README.md`; no icon files are committed | `assets/icons/` |

All three wallpapers are 3840×2160, self-contained SVG (no external references,
no embedded fonts, no raster data), and are designed with a calm centre so light
icons and window content stay readable on top. `continuity-dark-01.svg` is the
default; `config/hypr/hyprpaper.conf` selects it, and
`continuity-shell` picks a variant per workspace-worth of randomness if you set
`CONTINUITY_WALLPAPER_ROTATE=1`.

## Why SVG

* One file serves 1080p, 1440p and 4K panels without upscaling artefacts.
* The colour ramps can be regenerated from a single accent hue by `matugen`, so
  a user can re-theme the whole shell to their own wallpaper without new assets.
* `hyprpaper` renders SVG through its image loader; if you use `swaybg` instead,
  keep the SVG for tier-1 fidelity and let the toolkit rasterise it.

## Rasterisation (install.sh does this)

`hyprpaper` is not guaranteed to have an SVG loader built in — it depends on how
it was compiled against `librsvg`. So `install.sh --user` rasterises each SVG to
PNG at 3840×2160 with `rsvg-convert` (package `librsvg`) when that tool is
available, and writes the result next to the SVG as
`continuity-dark-0N.png`. `config/hypr/hyprpaper.conf` prefers the PNG and falls
back to the SVG. If neither `rsvg-convert` nor an SVG-capable `hyprpaper` is
present, `continuity-shell` falls back to `swaybg`, and lastly to a flat dark
background — the session must never fail to start over a wallpaper.

The SVGs remain the source of truth: edit them, never the generated PNGs.

## Licensing

Assets authored for this project (everything listed above) are released under
**CC0-1.0 / public domain** in line with the rest of the ContinuityOS profile, so
they can be redrawn, recoloured and redistributed without attribution.

Inherited upstream assets are **not** covered by that and must be checked
individually if you vendor them:

* Papirus icon theme — GPL-3.0-or-later (see `icons/README.md`).
* Any wallpaper you add yourself — put the licence in this table when you add it.

## Adding an asset

1. Put the file under the right subdirectory here.
2. Add a row to the table above with the licence.
3. Reference it from `config/` using `$CONTINUITY_ASSET_DIR` — never with a bare
   `~/...` path, because Waybar and Eww do not expand `~` inside config values.
4. Re-run `./install.sh --user` (idempotent) to copy it into place.
