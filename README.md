# Steam Big Picture Game Mode on Fedora

A SteamOS-style **Game Mode** on stock Fedora KDE: boot straight into Steam's
Deck UI running under gamescope as the DRM compositor, with HDR, VRR, the
MangoHud overlay, Steam Input, the on-screen keyboard, and a working
"Switch to Desktop" button.

Inspired by [Bazzite](https://github.com/ublue-os/bazzite), but without
switching to an immutable distro. This is a set of config files and a script
that wire up packages Bazzite already uses, on a normal Fedora install.

Verified on **Fedora 44 KDE**, AMD RX 9070 XT (RDNA4).

---

## Read this first

This is not a polished product. It edits your display manager, loads a local
SELinux policy module, and can make your machine boot into Steam instead of a
desktop. All of it is reversible, but **know the escape hatches before you
start**:

- **`Ctrl`+`Alt`+`F3`** gets you a TTY from Game Mode.
- If autologin traps you: `sudo rm /etc/sddm.conf.d/10-gamemode-autologin.conf && sudo systemctl restart sddm`
- If there is no GUI at all: add `systemd.unit=multi-user.target` at the GRUB
  prompt to boot with no display manager.
- `./uninstall.sh --restore-dm plasmalogin` puts things back.

**Test `--core` first.** It only adds a session entry to your login screen and
changes nothing else. Pick "Steam Big Picture" from the session menu and confirm
it works before enabling anything that logs you in automatically.

### What each stage costs you

| Stage | What it changes | Risk |
|---|---|---|
| `--core` | Adds a pinned repo, installs 7 packages, one config file | Low. No display-manager changes. |
| `--session-switching` | **Replaces your display manager with SDDM**, loads an SELinux module, appends to a package-owned file | Medium. Reversible, old DM package is kept. |
| `--autologin` | Boots into Game Mode every time | Medium. `Relogin=true` means the login screen is no longer a way out. |
| `--conditional-autologin` | Boots into Game Mode only when HDMI is connected | Medium, same as above but self-limiting. |

### Specific warnings

- **The SELinux module grants `init_t` write access to `tracefs`.** It is
  needed because `steamos-manager` creates a tracefs instance to watch OOM
  kills, and dies without it. The source is in
  [`selinux/`](selinux/steamos_manager_tracefs.te) with comments — read it and
  decide for yourself. It is broader than the exact denials observed, to avoid
  a new denial on every restart.
- **`--session-switching` replaces your display manager.** `steamos-manager`
  has SDDM paths compiled into it (`/etc/sddm.conf.d`, `zzt-holo-temp-login.conf`)
  and no knowledge of anything else. On Fedora 44 KDE that means replacing
  `plasma-login-manager`. Bazzite does the same thing for the same reason. The
  old package is left installed so you can switch back.
- **`platform.toml` is package-owned.** The `[session]` block gets appended to
  `/usr/share/steamos-manager/platform.toml`; a `steamos-manager` update will
  revert it and switch-to-desktop will silently stop working. Re-run
  `install.sh --session-switching` to reapply.
- **Terra is pinned, deliberately.** It carries ~3000 packages including a full
  Mesa stack. `install.sh` restricts it to six via `includepkgs` so it can never
  win an upgrade for anything else on your system. Do not remove that pin.
- **The crash-recovery fallback is untested here.** The session watchdog gives
  up after 5 sessions shorter than 60s and is wired to drop you to the desktop.
  The mechanism underneath is the same one the Switch to Desktop button uses, so
  it is probably fine, but it has not been deliberately triggered.

---

## Requirements

- Fedora 41+ (`dnf5`). Developed and tested on 44 KDE.
- Steam installed (RPM Fusion `nonfree-steam`).
- `gamescope` from Fedora. Check HDR support: `gamescope --help | grep hdr`
- `policycoreutils-python-utils` (for the SELinux module).
- AMD or Intel GPU recommended. NVIDIA is untested here; Bazzite needs extra
  work for it and so will you.

## Install

```sh
git clone https://github.com/downquark7/fedora-big-picture-gamemode
cd fedora-big-picture-gamemode

sudo ./install.sh --core            # start here, then log out and test
sudo ./install.sh --session-switching
sudo ./install.sh --conditional-autologin
# or, once you know what you are doing:
sudo ./install.sh --all
```

Reboot, then verify:

```sh
steamosctl get-valid-desktop-sessions    # should list your desktop session
journalctl --user -u 'gamescope-session-plus@steam.service' -b | grep gamescope
```

## Configure

Edit `/etc/gamescope-session-plus/sessions.d/steam`. It is sourced *after* the
vendor file, so it only holds your deltas. Per-user overrides go in
`~/.config/gamescope-session-plus/sessions.d/steam`.

The two you will most likely want:

```sh
OUTPUT_CONNECTOR="HDMI-A-1,DP-1,*"   # priority order; first CONNECTED wins
ENABLE_GAMESCOPE_HDR=1               # off by default
```

List your connectors:

```sh
for d in /sys/class/drm/card*-*/; do echo "$(basename $d): $(cat $d/status)"; done
```

---

## How it works

```
display manager (SDDM)
└─ /usr/share/wayland-sessions/gamescope-session-steam.desktop
   └─ gamescope-session-plus steam            (shim: fixes dbus env, unsets DISPLAY)
      └─ gamescope-session-plus@steam.service
         └─ /usr/share/gamescope-session-plus/gamescope-session-plus
            ├─ sources sessions.d/steam  → ~40 STEAM_* flags + CLIENTCMD
            ├─ launches gamescope (DRM compositor)
            ├─ launches mangoapp (the overlay)
            └─ launches: steam -gamepadui -steamos3 -steampal -steamdeck

steamos-manager (system + user D-Bus daemon)
└─ steamosctl → TDP/GPU/fan (N/A on desktop) + session switching
```

`sessions.d/steam` is the file that makes Steam behave like a Deck: it exports
flags such as `STEAM_GAMESCOPE_HDR_SUPPORTED`, `STEAM_USE_MANGOAPP` and
`QT_IM_MODULE=steam` that the client probes at startup to decide which UI
features to enable.

Switch-to-desktop: Steam runs `steamos-session-select`, a dispatcher that execs
`/usr/libexec/os-session-select`. Ours calls `steamosctl switch-to-desktop-mode`,
and steamos-manager writes a one-shot SDDM drop-in and drops
`graphical-session.target`.

## Gotchas found the hard way

- **`SessionManagement1` is gated on an SDDM vendor marker.** Adding `[session]`
  to `platform.toml` is necessary but not sufficient — steamos-manager also
  requires `holo.conf` or `steamos.conf` in `/usr/lib/sddm/sddm.conf.d`. Without
  it the interface is not exposed at all and every `steamosctl` session verb
  returns `UnknownInterface` with no hint why. Undocumented; found by
  string-searching the binary.
- **`systemctl disable` does not stop D-Bus activation.** steamos-manager kept
  being started by Steam calling its bus name. Use `mask`.
- **`StartLimitBurst=5`.** After a few failed starts systemd refuses to try
  again and logs `Start request repeated too quickly` — which looks like your fix
  failed when it was never attempted. `systemctl reset-failed` first.
- **gamescope picks its output once, at startup.** Plugging in a
  higher-priority display mid-session does nothing; it will not migrate.
- **A TV plugged in but powered off reports `disconnected`.** Rebooting usually
  puts a TV into standby, which is exactly when conditional autologin checks. Use
  `/etc/gamemode-autologin.force`, or enable your TV's "Quick Start" / "Instant
  On" setting to keep HPD asserted in standby.
- **CEC is not available on discrete AMD GPUs.** The `cec` kernel module being
  loaded is misleading — amdgpu uses the CEC *notifier* (to publish the HDMI
  physical address), and never registers an adapter. `cec-ctl --list-devices`
  returns empty. You would need a USB CEC dongle.
- **`steamos-manager-gamescope-session-plus` is broken packaging.** It ships its
  symlink nested inside a directory of its own name, under a `.wants` named for a
  non-templated unit that does not exist. A no-op; harmless.
- **Do not `source` the vendor `sessions.d/steam` to inspect it.** It has side
  effects: sets your GTK-3 cursor theme to `steam`, touches Steam config, and
  spawns `steam_notif_daemon`.

## Optional extras

These are independent of the stages above and can be installed on their own.

### `--controller-wake`: wake from sleep with a Steam Controller

```sh
sudo ./install.sh --controller-wake
```

For the Steam Controller (2026) on its USB Puck. Two parts:

- **A udev rule** (`61-steam-controller-wake.rules`). `steam-devices` already
  enables USB wakeup on the Puck, but not on the root hub it sits under, so the
  wake signal never reaches the system. The rule enables wakeup on every parent
  up the chain.
- **`steam-controller-off.service`**, which turns controllers off right before
  suspend. Once wakeup works, a controller that is still on wakes the PC again
  a few seconds after it sleeps. Steam does not know about a suspend triggered
  outside it, so the script sends the controller's own power-off command
  (feature report `0x9F` with payload `off!`, the same one SDL and community
  tools use) to each Puck slot over hidraw. Empty slots reject it, which is
  ignored.
- **`steam-controller-off-shutdown.service`** runs the same script on power
  off, so controllers don't stay on after the PC shuts down. Reboots are left
  alone so the controller is still connected when the PC comes back.

Press the Steam button to wake. If the PC still wakes up on its own, another
device behind the same USB controller is probably doing it; a wireless mouse
receiver is the usual culprit. `grep . /sys/bus/usb/devices/*/power/wakeup`
lists what can wake the system.

### `--sleep-webhooks`: run something on sleep and wake

```sh
sudo ./install.sh --sleep-webhooks
sudoedit /etc/default/sleep-webhooks    # set SLEEP_URL / WAKE_URL
/usr/libexec/sleep-webhook sleep        # test without suspending
```

POSTs `SLEEP_URL` before suspend and `WAKE_URL` after resume, for example Home
Assistant webhooks that turn the TV off and on. Leave either empty to skip it.

- The sleep call times out after 3 seconds so it never holds up suspend.
- After resume the network takes a few seconds to come back, so the wake call
  retries for up to a minute.
- A failed webhook never fails the unit or blocks sleep.

Check what happened on the last cycle with
`journalctl -b -u webhook-sleep -u webhook-wake`.

## Uninstall

```sh
sudo ./uninstall.sh --restore-dm plasmalogin   # or gdm, etc
sudo ./uninstall.sh --purge --restore-dm plasmalogin
```

## Licence and attribution

Original work is MIT (see [`LICENSE`](LICENSE)). Several files are derived from
Bazzite (Apache-2.0) and are marked as modified in their headers.
See [`NOTICE.md`](NOTICE.md) for per-file attribution and
[`LICENSES/`](LICENSES/) for full texts.

Credit to [Bazzite](https://github.com/ublue-os/bazzite) /
[Universal Blue](https://universal-blue.org/),
[ChimeraOS](https://github.com/ChimeraOS/gamescope-session),
[Fyra Labs' Terra](https://terra.fyralabs.com/), and Valve.
