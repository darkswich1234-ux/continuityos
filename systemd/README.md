# ContinuityOS systemd units & pacman hooks

The former UMU runtime seed/verify units and hook remain only for uninstall
compatibility; host-native Proton launches do not use a Steam Linux Runtime container,
so these legacy units are not installed/enabled.

`install.sh` splits this directory by scope. Nothing here is enabled by hand:

| File | Destination | Enabled as |
|---|---|---|
| `continuity-umu-seed.service` | `/usr/lib/systemd/user/` | user unit, pulled in by `graphical-session.target` |
| `continuity-umu-verify.service` | `/usr/lib/systemd/user/` | started only by the timer below |
| `continuity-umu-verify.timer` | `/usr/lib/systemd/user/` | `systemctl --user enable --now continuity-umu-verify.timer` |
| `continuity-first-boot.service` | `/etc/systemd/system/` | `systemctl enable continuity-first-boot.service` (runs once, then `ConditionPathExists` retires it) |
| `continuity-winboat.service` | `/etc/systemd/system/` | only installed with `install.sh --with-winboat`; **not** enabled by default |
| `pacman/hooks/*.hook` | `/etc/pacman.d/hooks/` | automatic (ALPM) |

## What each unit is for

**`continuity-first-boot.service` (system, oneshot, once)**
Runs `/usr/local/bin/continuity-first-boot` on the first boot after an install and
creates `/var/lib/continuity/first-boot.done` afterwards. Because the marker is
touched by `ExecStartPost`, a failed provisioning run is retried on the next boot.
`/etc/continuity/install.conf` (written by `install.sh`) carries machine-wide choices
such as the selected components; it is optional, hence `EnvironmentFile=-`.

**`continuity-winboat.service` (system, oneshot, optional)**
Supervises the WinBoat backend for Windows utilities that Proton/Wine cannot run.
Requires `/dev/kvm`, so it is only installed with `--with-winboat`. Upstream ships no
systemd unit of its own; see the comment block in the file — if upstream ever adds
one, prefer it and delete this.

## Checking status

```bash
systemctl status continuity-first-boot.service
continuity-shakedown
```
