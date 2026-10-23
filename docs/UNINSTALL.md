# Uninstalling ContinuityOS

Everything `install.sh` does is additive and named, so removal is mechanical. Use the
shipped helper for the normal case, or follow the manual list below to remove exactly
what you want.

## The easy way

```bash
continuity-uninstall --dry-run     # show what would be removed
continuity-uninstall               # remove system + user files
continuity-uninstall --system      # system files only (run with sudo)
continuity-uninstall --user        # this user's config/data only
```

`continuity-uninstall` is a copy of `tools/uninstall.sh` installed to
`/usr/local/bin/continuity-uninstall`. It never deletes packages.

`--system` (and the default, which does both) runs **`continuity-boot off` first**,
before it removes the session binary. The order matters: this machine currently
boots straight into a session that is about to be deleted, and an autologin pointing
at a file that no longer exists is a login loop. `off` strips the autologin and
re-enables `getty@tty1`, leaving you able to log in — see [BOOT.md](BOOT.md).

## Manual removal

### 1. Stop and disable the services first

```bash
# user-scope units (runtime seeding/verification)
systemctl --user disable --now continuity-umu-verify.timer continuity-umu-seed.service 2>/dev/null
systemctl --global disable continuity-umu-seed.service continuity-umu-verify.timer 2>/dev/null
systemctl --user daemon-reload

# system-scope units (first boot, optional WinBoat bridge)
sudo systemctl disable --now continuity-winboat.service 2>/dev/null
sudo systemctl disable continuity-first-boot.service 2>/dev/null
sudo systemctl daemon-reload

# the login manager — only if you are removing greetd too
sudo continuity-boot off                 # strips the autologin, re-enables getty@tty1
sudo systemctl disable --now greetd.service 2>/dev/null
sudo systemctl daemon-reload
```

`continuity-boot off` alone is enough to stop the no-prompt boot; the `disable` above
is only for taking greetd out of the picture entirely.

### 2. System files (root)

| Path | Note |
|---|---|
| `/usr/local/bin/continuity-run`, `continuity-prefix`, `continuity-gaming-mode`, `continuity-umu-verify`, `continuity-panel`, `continuity-shell`, `continuity-session-start`, `continuity-screenshot`, `continuity-first-boot`, `continuity-uninstall`, `continuity-wizard`, `continuity-boot`, `continuity-region`, `continuity-export`, `continuity-shakedown` | the CLI |
| `/usr/local/lib/continuity/` | `continuity-common.sh` and the directory |
| `/usr/share/continuity/` | config snapshot, `umu-runtimes/` |
| `/usr/share/backgrounds/continuity/` | converted wallpaper PNGs |
| `/usr/share/applications/continuity-*.desktop` | MIME handler + tool entries |
| `/usr/share/applications/mimeapps.list` | only if your install wrote associations there (this profile writes `/etc/xdg/mimeapps.list`) |
| `/etc/xdg/mimeapps.list` | system-wide `.exe` associations |
| `/usr/share/wayland-sessions/continuity.desktop` | the login-screen session entry |
| `/etc/pacman.d/hooks/98-continuity-desktop-db.hook`, `99-continuity-umu.hook` | ALPM hooks |
| `/etc/systemd/system/continuity-first-boot.service`, `continuity-winboat.service` | system units |
| `/usr/lib/systemd/user/continuity-umu-seed.service`, `continuity-umu-verify.service`, `continuity-umu-verify.timer` | user units |
| `/etc/greetd/config.toml` | the login manager config, rendered from `config/greetd/config.toml.tmpl`. `continuity-boot off` deliberately leaves it in place (autologin block removed) so switching back is a render, not a reinstall; delete it to leave greetd unconfigured. |
| `/etc/systemd/system/greetd.service.d/10-continuity-live.conf` | only ever present if an older install copied the live medium's ordering drop-in onto a real machine |
| `/etc/continuity/` | `install.conf` |
| `/var/lib/continuity/` | first-boot marker |
| `/etc/skel/.config/continuity/environment.conf` | defaults written for *future* users only |

```bash
sudo rm -f /usr/local/bin/continuity-{run,prefix,gaming-mode,umu-verify,panel,shell,session-start,screenshot,first-boot,uninstall,wizard,boot,region,export,shakedown}
sudo rm -rf /usr/local/lib/continuity /usr/share/continuity /usr/share/backgrounds/continuity
sudo rm -f /etc/greetd/config.toml
sudo rm -f /etc/systemd/system/greetd.service.d/10-continuity-live.conf
sudo rmdir /etc/greetd 2>/dev/null
sudo rm -f /usr/share/applications/continuity-*.desktop
sudo rm -f /usr/share/wayland-sessions/continuity.desktop
sudo rm -f /etc/xdg/mimeapps.list
sudo rm -f /etc/pacman.d/hooks/98-continuity-desktop-db.hook /etc/pacman.d/hooks/99-continuity-umu.hook
sudo rm -f /etc/systemd/system/continuity-first-boot.service /etc/systemd/system/continuity-winboat.service
sudo rm -f /usr/lib/systemd/user/continuity-umu-seed.service /usr/lib/systemd/user/continuity-umu-verify.service /usr/lib/systemd/user/continuity-umu-verify.timer
sudo rm -rf /etc/continuity /var/lib/continuity
sudo rm -f /etc/skel/.config/continuity/environment.conf
```

### 3. Your user files

| Path | What it is |
|---|---|
| `~/.config/continuity/` | `environment.conf` (engine tuning) and `region.conf` (locale and time zone, written by `continuity-region`) |
| `~/.config/hypr/`, `~/.config/waybar/`, `~/.config/eww/`, `~/.config/rofi/`, `~/.config/dunst/` | shell configuration |
| `~/.config/hypr/local.conf` | **your** Hyprland overlay: ContinuityOS writes one fenced `input { kb_layout = … }` block into it, so remove that block if you want to keep the rest |
| `~/.config/environment.d/10-continuity-region.conf` | the locale/time zone again, for `systemd --user` (remove this file, not the directory) |
| `~/.local/state/continuity/replaced/` | copies that `continuity-export import --replace` moved aside instead of deleting |
| `~/.local/share/universal-prefixes/` | **every Windows prefix and its `drive_c`** — deleting this is what wipes your installed Windows apps |
| `~/.local/share/umu/` | downloaded Steam Linux Runtimes (can be several GB) |
| `~/.local/share/continuity/` | wallpapers and converted icons |
| `~/.local/share/applications/continuity/` | generated per-app launchers |
| `~/.local/share/applications/continuity-wine.desktop` | the `.exe` handler entry |
| `~/.local/state/continuity/` | logs, gaming-mode state and marker |
| `~/.cache/umu/` | runtime download cache |
| `~/.config/mimeapps.list` | your per-user `.exe` associations |

```bash
rm -rf ~/.config/continuity ~/.config/hypr ~/.config/waybar ~/.config/eww ~/.config/rofi ~/.config/dunst
rm -f  ~/.config/environment.d/10-continuity-region.conf
rm -rf ~/.local/share/continuity ~/.local/share/applications/continuity
rm -f  ~/.local/share/applications/continuity-wine.desktop
rm -rf ~/.local/state/continuity ~/.cache/umu
rm -f  ~/.local/share/umu -r        # only if you do not want the runtimes back
rm -rf ~/.local/share/universal-prefixes
```

Before deleting prefixes you care about, archive them:

```bash
continuity-prefix export mygame ~/backups/mygame.tar.zst
```

### 4. Remove the `~/.config/mimeapps.list` associations

`install.sh --system` wrote lines such as
`application/x-ms-dos-executable=continuity-wine.desktop` into
`~/.config/mimeapps.list`. Edit the file and delete those keys, or reset the type:

```bash
xdg-mime default org.gnome.FileRoller.desktop application/x-msdownload   # or leave unset
```

### 5. Restore the backups

`install.sh` keeps the two files it may have edited:

| Backup | Restore with | When it exists |
|---|---|---|
| `/etc/pacman.conf.continuity-backup` | `sudo cp -a /etc/pacman.conf.continuity-backup /etc/pacman.conf && sudo pacman -Sy` | only if `[multilib]` had to be enabled |
| `~/.config/continuity/environment.conf.continuity-backup` | `cp -a ~/.config/continuity/environment.conf.continuity-backup ~/.config/continuity/environment.conf` | when a previous `environment.conf` was replaced by a re-run |

### 6. Packages (optional, and worth thinking about)

`install.sh` only ever installs packages with `pacman -S --needed`, so nothing is
upgraded behind your back. The exact sets are in `packages/core.list`,
`packages/desktop.list`, `packages/gaming.list`, `packages/creative.list`,
`packages/*.list` (`core`, `desktop`, `gaming`, `creative`, `aur`) — note that the
graphics stack has no list file of its own: `install.sh` selects it from GPU
detection in `install_graphics`.

Many of those packages are shared with unrelated software (`mesa`, `pipewire`,
`networkmanager`, `git`, `python`). Removing them blindly with `pacman -Rns` can take
your system with them. If you want to unwind, remove only the unmistakably
ContinuityOS-shaped ones and let pacman tell you what else depends on them:

```bash
sudo pacman -Rns hyprland waybar eww hyprpaper hypridle hyprlock hyprland-qtutils
# and, if nothing else needs them:
sudo pacman -Rns umu-launcher protontricks gamescope mangohud goverlay winetricks
# the login manager ContinuityOS installs (packages/core.list: "greetd", "greetd-tuigreet"):
sudo pacman -Rns greetd greetd-tuigreet      # run `continuity-boot off` FIRST
```

Removing `greetd` while the autologin is still configured takes away the autologin
*and* the greeter at once, which leaves you at a plain TTY with no session menu —
recoverable (`login`, then `continuity-shell`), but not what you want to discover by
rebooting. `continuity-boot off` first, then remove the packages if you do not want a
login manager at all.

Keep `mesa`, `vulkan-*`, `lib32-*`, `pipewire` and `networkmanager` unless pacman
confirms nothing else uses them.

### 7. What is intentionally left behind

- Your Steam library and `steamapps/compatdata` — ContinuityOS never wrote there;
  Steam's own uninstall handles it.
- Files in `~/Pictures/Screenshots`, any prefix archive you exported, and anything
  `continuity-export import` placed in `~/.local/state/continuity/replaced/`.
- `~/.local/share/umu` if you skipped that removal step; it is only a runtime cache.
- `/etc/greetd/config.toml` when you turned the autologin off: `continuity-boot off`
  keeps the file (minus the autologin block) so a later `on` needs no reconstruction.
