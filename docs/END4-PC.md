# Private end4-pC prototype

`end4-pC` is pctrade's GPL-3.0 personal fork of end-4's illogical-impulse shell. It is an optional **user-level Quickshell overlay**, not an operating system or standalone desktop. The upstream README says it expects illogical-impulse to be installed and running. ContinuityOS keeps it separate from its UMU/Proton compatibility engine and its own Hyprland/Eww shell.

## Pinned scaffold

The repository's `bin/continuity-end4-pc` helper is installed as `continuity-end4-pc`. It stages the upstream repo at:

```text
${XDG_CONFIG_HOME:-~/.config}/quickshell/end4-pC
```

The source is `https://github.com/pctrade/end4-pC.git`, pinned to commit `4de3f593cb220194fd2f87c1e344b775482ad9aa`. Upstream currently publishes no release tags; this is a commit pin, not a signed release. Review the code and license before running it, and update the pin only after testing a reviewed revision. The clone is not bundled into the ISO or automatically fetched during installation.

```sh
continuity-end4-pc status
continuity-end4-pc install   # network access; only clones the overlay
continuity-end4-pc launch   # runs qs -c end4-pC; appends output to the private state log
```

The helper refuses to overwrite an existing destination, verifies the origin and exact commit, and does not install the prerequisite, modify Hyprland configuration, change the default shell, or kill other `qs` processes. Its launch log is `~/.local/state/continuity/end4-pC.log` (or the XDG state path), created with owner-only permissions. Inspect it with `tail -n 200 ~/.local/state/continuity/end4-pC.log` after a failed launch.

## Prerequisite and opt-in default

Install illogical-impulse separately using its current upstream instructions, review the installer and the changes it proposes, then install the overlay. Upstream's current docs say CachyOS should work, but package differences can occasionally matter. Its instructions also warn that the project supplies user-level customization only; it does not provision drivers or other system foundations.

Only after you have manually tested `continuity-end4-pc launch`, you may opt in to making it the Quickshell config loaded by illogical-impulse. Upstream's current documented switch is in `~/.config/hypr/hyprland/variables.lua`:

```lua
hl.env("qsConfig", "ii")
```

Change `ii` to `end4-pC` only if that exact line exists in your installed base version. Back up the file first. ContinuityOS does not automate this edit: it must not replace or silently rewrite the existing Hyprland startup. Revert the one value to `ii` to restore the base shell. Existing ContinuityOS Waybar/Eww/Dunst services may visually overlap with another shell; test in a disposable user or VM before enabling the overlay at login.

The upstream overlay is GPL-3.0. Keep its license and notices intact; redistribution or modification has corresponding GPL source and notice obligations. This scaffold keeps the checkout in the user's home and is intended for private prototyping, not for silently bundling upstream code into a public image.

## Debugging a guest OS

Use a VM as a separate test target; Proton/UMU runs Windows applications and is not a VM debugger. For a QEMU system guest, QEMU documents `-s -S` to expose its GDB stub on TCP port 1234 and pause the guest until GDB resumes it:

```sh
qemu-system-x86_64 ... -s -S
# In another terminal, with the matching guest symbols and architecture:
gdb ./vmlinux
gdb> target remote localhost:1234
gdb> continue
```

Keep that endpoint bound to loopback and do not forward it to a LAN or the public internet: QEMU's GDB stub has no authentication and grants powerful control over the guest. For Windows kernel debugging, ordinary GDB is not a complete replacement for WinDbg; Microsoft documents an EXDI bridge for QEMU and separately recommends considering KDNET. QEMU/libvirt/VirtualBox logging and their boot configuration are hypervisor-specific. No VM is launched or port opened by ContinuityOS automatically.

## Sources

- [end4-pC upstream README](https://github.com/pctrade/end4-pC)
- [Pinned upstream commit](https://github.com/pctrade/end4-pC/commit/4de3f593cb220194fd2f87c1e344b775482ad9aa)
- [illogical-impulse install/update docs](https://ii.clsty.link/en/ii-qs/01setup/)
- [QEMU GDB usage](https://qemu-project.gitlab.io/qemu/system/gdb.html)
- [Microsoft: QEMU kernel debugging with EXDI](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/setting-up-qemu-kernel-mode-debugging-using-exdi)
