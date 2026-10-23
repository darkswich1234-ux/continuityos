# Hyprland config: hyprlang `.conf` today, Lua next

ContinuityOS ships `config/hypr/*.conf` in **hyprlang** syntax and treats those files
as the source of truth. Hyprland now also accepts a Lua configuration
(`hyprland.lua`) and prefers it for new configurations, while continuing to read
hyprlang configs for the time being. Nothing in this repo needs to change yet; this
page exists so the eventual migration is a known quantity rather than a surprise.

## The state of play

- `.conf` / hyprlang is **deprecated over time, not removed**. Hyprland reads it and
  is expected to keep doing so for a few releases after the Lua config landed.
- If both a `hyprland.conf` and a `hyprland.lua` are present, only one is used
  (Lua wins). Do not keep both in `~/.config/hypr/` and expect the `.conf` to apply.
- ContinuityOS overrides live in `~/.config/hypr/local.conf`, sourced by
  `hyprland.conf`. A Lua config would need its own include mechanism.

Unknown `hyprlang` keys are warned about rather than fatal, but a deprecated key
silently doing nothing is the worst failure mode — worth checking after any upgrade.

## Before / after

Both examples below are the *shapes* to expect. **Verify field names against the
Hyprland documentation for the version you actually have installed** before trusting
them; the Lua API is younger than hyprlang and has moved.

### An animation

Today (`config/hypr/conf.d/animations.conf`):

```ini
bezier = spring, 0.22, 1.0, 0.36, 1.0
bezier = leave,  0.4, 0.0, 1.0, 1.0

animations {
    enabled = true
    animation = windowsIn,  1, 4.5, spring, popin 85%
    animation = windowsOut, 1, 3.0, leave,  popin 92%
    animation = layersIn,   1, 3.5, spring, fade
    animation = workspaces, 1, 4.0, spring, slide
}
```

Lua, roughly:

```lua
-- Illustrative: confirm the exact call names/fields with the docs for your build.
hl.bezier("spring", 0.22, 1.0, 0.36, 1.0)
hl.bezier("leave", 0.4, 0.0, 1.0, 1.0)

hl.animation("windowsIn",  { enabled = true, speed = 4.5, curve = "spring", style = "popin 85%" })
hl.animation("windowsOut", { enabled = true, speed = 3.0, curve = "leave",  style = "popin 92%" })
hl.animation("workspaces", { enabled = true, speed = 4.0, curve = "spring", style = "slide" })
```

Note the semantics that do **not** change: `speed` is an animation *parameter*, not a
duration in milliseconds, and disabling an animation (`enabled = false`, or
`hyprctl keyword animations:enabled false` at runtime) is what gaming mode relies on.

### A window rule

Today (`config/hypr/conf.d/rules.conf`), current hyprlang rule grammar:

```ini
windowrule = match:class ^(steam_app_\d+)$, noblur, noanim, immediate
layerrule  = blur on, match:namespace drawer
```

Lua, roughly:

```lua
hl.window_rule({ match = { class = [[^(steam_app_\d+)$]] }, actions = { "noblur", "noanim", "immediate" } })
hl.layer_rule({ match = { namespace = "drawer" }, actions = { "blur on" } })
```

The old `windowrulev2 = <effect>, <class:regex>` form is dead in **both** syntaxes —
it was replaced around Hyprland 0.53 by the match-first grammar you see above.

## Governing run-time keywords for the `continuity-*` tools

`continuity-gaming-mode` drives the compositor through `hyprctl keyword`, which is
config-format independent — the same keywords are used for the `.conf` and Lua
configs, so gaming mode keeps working across a migration. The keywords it sets are
`animations:enabled`, `decoration:blur:enabled`, `decoration:shadow:enabled`,
`decoration:rounding`, `general:gaps_in`, `general:gaps_out`, `general:border_size`
and `misc:disable_autoreload`. If a future release renames any of them, gaming mode is
the only thing that needs updating, and `continuity-gaming-mode status` will show
`Animations: unknown` when `hyprctl getoption` stops recognising a name.

## If you want to migrate

1. Read the Hyprland docs for your installed version:

   ```bash
   hyprctl version
   ```

2. Translate one file at a time, keeping the `.conf` files in the repo as the
   reference implementation, and run `hyprctl reload` after each file rather than
   restarting the session.
3. Move runtime state out of the config: gaming mode and the drawer toggles in
   `bin/continuity-*` are already format-independent, so keep them there.
4. When a translated Lua config is proven on your hardware, open the change against
   `config/hypr/` and update this page — it is the only document that claims hyprlang
   is what ships.
