# Booting straight into ContinuityOS

A stock Arch install gives you two things before you reach a desktop: a TTY login,
and then a session chooser. That is `Arch → Hyprland → ContinuityOS`, and it is
the single most annoying part of running a desktop on Arch. ContinuityOS removes
both steps: power on, and the desktop is simply there.

```
  power on ──▶ greetd ──▶ continuity-shell ──▶ Hyprland + the ContinuityOS shell
                 │
                 └─ (only after a logout) tuigreet ──▶ pick a session
```

## How it works, in one paragraph

The login manager is [greetd](https://wiki.archlinux.org/title/Greetd), configured
in `/etc/greetd/config.toml`. Its `[initial_session]` section is the whole trick:
greetd starts that command **once**, when it comes up, and it *bypasses the greeter
completely* — no password, no session menu. It is not a greeter with the password
field hidden; the greeter is never started. `[default_session]` is therefore not
the boot path at all: it is what appears **after a logout** (or if the session dies
on its own). Keeping a working greeter there is deliberate — a machine whose only
way in is a desktop that might be broken is a machine you reinstall.

The file is rendered from [`config/greetd/config.toml.tmpl`](../config/greetd/config.toml.tmpl)
by `continuity-boot`, so there is one source of truth for the format. Edit the
template or use the tool — not `/etc/greetd/config.toml` by hand, because
`continuity-boot on` renders that file from the template again.

## The commands

```bash
continuity-boot status              # what this machine does at boot, right now
continuity-boot status --json       # ...for the shell widgets
continuity-boot doctor              # walk the whole chain, one check at a time
sudo continuity-boot on             # boot into the desktop as the invoking user
sudo continuity-boot on --user anna # ...as somebody else
sudo continuity-boot off            # back to a TTY login (fully reversible)
sudo continuity-boot on --greeter agreety --vt 2
sudo continuity-boot on --dry-run   # print the config and the commands, change nothing
```

`install.sh` drives the same tool, so the installer and the CLI cannot drift:

| You ran | What happens at boot |
|---|---|
| `sudo ./install.sh --all` (or `--system`) | autologin is configured; the summary says so |
| `... --no-autologin` | a login prompt is kept, and `continuity-boot off` is applied |
| `... --no-enable` | units are copied but nothing is enabled — the boot path is left alone |
| `... --dry-run` | the rendered config is printed, nothing is written |

The choice is recorded as `CONTINUITY_AUTOLOGIN=` in `/etc/continuity/install.conf`
so first-boot work and `continuity-boot doctor` can tell what this machine was
*asked* to do rather than inferring it from greetd's state.

## What it refuses to do

An autologin that goes wrong is the one mistake you cannot fix from the desktop you
cannot reach, so every refusal below happens **before a single byte is written**:

* **no session** — `/usr/local/bin/continuity-shell` missing or not executable.
  Autologin into nothing is a black screen. `sudo ./install.sh --system` fixes it.
* **no account** — the target does not exist, is `root`, or has a `nologin`/`false`
  shell. (`--user` defaults to `$SUDO_USER`, precisely so this is not typed by hand.)
* **a second display manager** — if `sddm`, `lightdm`, `gdm` or similar is enabled,
  two managers fighting over the seat is a black screen. The error prints the exact
  `systemctl disable` line to run first.
* **a malformed render** — the config is written to a temp file, checked for
  `[default_session]`, for the presence (or absence, for `off`) of
  `[initial_session]`, and for unsubstituted `@PLACEHOLDER@` tokens, and only then
  moved into place. A failed render leaves the previous config untouched.

It does **not** touch `getty@tty1.service`, and it does not mask anything: greetd's
own unit already has `Conflicts=getty@tty1.service` plus
`Alias=display-manager.service`, so the two cannot run together, and tty2 onwards
stay available as a recovery route. `systemctl cat greetd` shows the unit your
package actually ships.

## The greeter is the recovery path

`continuity-boot off` disables the unit and re-enables `getty@tty1`, so the machine
boots to a normal TTY login again — log in and run `continuity-shell` to get the
desktop. That is also what `tools/uninstall.sh` does *before* deleting the session
binary, because an autologin pointing at a file that no longer exists is a login
loop.

On a machine whose desktop will not start, the greeter is deliberately a general
one (`tuigreet --cmd …`, or `agreety`): from there you can pick a plain session,
log in, and repair things. `--greeter none` is allowed and renders `/bin/sh` as the
default session, but that is a kiosk choice, not a desktop one — a logout then drops
you to a shell as the unprivileged `greeter` account, and recovery is on tty2.

## One caveat worth knowing before you debug session type

greetd does not set `XDG_SESSION_TYPE` before PAM opens the session, so `logind` may
record the session as `unspecified` even though it is a Wayland session. Applications
behave correctly because `continuity-shell` exports `XDG_SESSION_TYPE=wayland`,
`XDG_CURRENT_DESKTOP=Hyprland` and `XDG_SESSION_DESKTOP=ContinuityOS` itself, and
`continuity-shell` also imports them into `systemd --user` for dbus-activated
services. The logind-level fix is a custom PAM service with `pam_env`, documented on
the Arch wiki; it is **deliberately not applied here**, because it would affect every
session greetd spawns, the greeter included. Check what your machine thinks with:

```bash
loginctl show-session "$XDG_SESSION_ID" -p Type
systemctl --user status continuity-umu-seed.service
```

## The live medium uses the same mechanism

`iso/profile/airootfs/root/.automated_script.sh` provisions the live root from the
embedded payload and then configures greetd for the `continuity` live account with
the same tool, with a documented fallback config for the case where the payload is
missing. The live desktop launches the **disk installer** instead of the first-run
wizard — configure-in-RAM is not a first-run experience — and the live session's
autologin needs no password because `[initial_session]` never authenticates anyone.

Two things to know about the live path:

* the session is ordered *after* the live hook (`greetd.service.d/10-continuity-live.conf`),
  because `[initial_session]` points at a binary that hook installs;
* that drop-in is **not** installed onto a real machine — `install.sh` skips
  anything under the ISO profile whose path mentions `live`.

## What has not been verified

Nothing in this repository has run on real Arch hardware. Specifically for the boot
path: no greetd has ever been started here, no autologin has ever booted anything,
and the greeter has never been seen. The template renders correctly (that is
checked by `tests/run.sh` against stub `systemctl`/`getent` fixtures, including the
refusals and `off`'s output), but rendering is not booting. Treat
`sudo ./install.sh --all --dry-run`, then a real `sudo continuity-boot on --dry-run`,
as the first honest test — and keep tty2 in mind while you do it.
