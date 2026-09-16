# Attribution and licensing

This repository is a mix of original work and files derived from upstream
projects. Original work is MIT (see `LICENSE`). Derived files remain under
their upstream licence, noted per-file and summarised here.

## Derived from Bazzite — Apache License 2.0

Source: <https://github.com/ublue-os/bazzite>
Copyright the Universal Blue contributors.
Full licence text: [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)

Apache-2.0 §4(b) requires modified files to carry prominent notices stating
that they were changed. Each file below carries such a notice in its header.

| File here | Derived from | Changes made |
|---|---|---|
| `files/usr/libexec/os-session-select` | `system_files/deck/shared/usr/libexec/os-session-select` | Dropped the `image-info.json` lookup (reads rpm-ostree image metadata that does not exist on traditional Fedora); desktop session is now autodetected or set via `/etc/default/gamemode-session`. Added a `desktop` case — upstream cases only on `plasma`/`plasma-wayland`/`*-persistent`, so the watchdog's own `steamos-session-select desktop` call falls through to `*)` and exits 1. |
| `files/usr/lib/sddm/sddm.conf.d/holo.conf` | `system_files/deck/shared/usr/lib/sddm/sddm.conf.d/holo.conf` | Session changed from `gamescope-session-ogui-steam.desktop` (OpenGamepadUI wrapper, handheld-oriented) to `gamescope-session-steam.desktop`. |
| `files/usr/libexec/gamemode-autologin` | `system_files/deck/shared/usr/libexec/bazzite-autologin` | Pattern only; rewritten. Condition swapped from "does `/etc/bazzite/desktop_autologin` exist" to an HDMI connector check. Added `state.conf` rewriting, `.force`/`.disable` overrides, and a DRM-probe wait. |

## Related — ChimeraOS `gamescope-session` (MIT)

Source: <https://github.com/ChimeraOS/gamescope-session>
Copyright © 2020-2023 Joaquín Ignacio Aramendía
Full licence text: [`LICENSES/MIT-ChimeraOS-gamescope-session.txt`](LICENSES/MIT-ChimeraOS-gamescope-session.txt)

No code from this project is redistributed here. `gamescope-session` and
`gamescope-session-steam` are installed as packages from Terra, and
`files/etc/gamescope-session-plus/sessions.d/steam` is an original override file
that their session script sources. Included for credit and because this
repository's documentation describes their design in detail.

## Packages installed, not redistributed

`install.sh` installs software from the [Terra](https://terra.fyralabs.com/)
repository (`gamescope-session`, `gamescope-session-steam`, `steamos-manager`,
`powerbuttond`, `steam-notif-daemon`) and from Fedora (`sddm`, `mangohud`).
Those carry their own licences; nothing from them is vendored here.

`steamos-manager` is Valve's, from
<https://gitlab.steamos.cloud/holo/steamos-manager>.
