#!/usr/bin/bash
#
# Reverse install.sh. Leaves packages installed by default (--purge removes).

set -euo pipefail

PURGE=0 ASSUME_YES=0 RESTORE_DM=""

die()  { echo >&2 "!! $*"; exit 1; }
info() { echo ":: $*"; }
warn() { echo >&2 "** $*"; }

while (( $# )); do
	case "$1" in
		--purge) PURGE=1 ;;
		--restore-dm) RESTORE_DM="${2:?--restore-dm needs a name, e.g. plasmalogin}"; shift ;;
		-y|--yes) ASSUME_YES=1 ;;
		-h|--help)
			cat <<'USAGE'
Usage: sudo ./uninstall.sh [--purge] [--restore-dm NAME] [-y]

  --purge            Also remove the Terra packages and the Terra repo pin.
  --restore-dm NAME  Re-enable this display manager (e.g. plasmalogin, gdm)
                     and disable SDDM.
USAGE
			exit 0 ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done

(( EUID == 0 )) || die "run with sudo"

info "Removing autologin"
rm -f /etc/sddm.conf.d/10-gamemode-autologin.conf
rm -f /etc/gamemode-autologin.force /etc/gamemode-autologin.disable
if systemctl is-enabled gamemode-autologin.service >/dev/null 2>&1; then
	systemctl disable gamemode-autologin.service
fi
rm -f /etc/systemd/system/gamemode-autologin.service /usr/libexec/gamemode-autologin

info "Removing session-switch hook and vendor marker"
rm -f /usr/libexec/os-session-select /usr/lib/sddm/sddm.conf.d/holo.conf

info "Removing session tuning"
rm -f /etc/gamescope-session-plus/sessions.d/steam
rm -f "/usr/lib/systemd/user/gamescope-session-plus@steam.service.wants/steamos-powerbuttond.service"

info "Removing controller wake support and sleep webhooks"
for u in steam-controller-off.service webhook-sleep.service webhook-wake.service; do
	systemctl disable "$u" >/dev/null 2>&1 || true
	rm -f "/etc/systemd/system/$u"
done
rm -f /usr/libexec/steam-controller-off /usr/libexec/sleep-webhook
rm -f /etc/udev/rules.d/61-steam-controller-wake.rules
udevadm control --reload >/dev/null 2>&1 || true
systemctl daemon-reload
warn "Leaving /etc/default/sleep-webhooks (your URLs) in place; delete it by hand."

info "Disabling steamos-manager"
for u in steamos-manager.service; do
	systemctl disable --now "$u" >/dev/null 2>&1 || true
done
systemctl disable --global steamos-manager.service steamos-manager-session-cleanup.service >/dev/null 2>&1 || true
# systemctl disable does NOT stop D-Bus activation; mask does.
systemctl mask steamos-manager.service >/dev/null 2>&1 || true
systemctl reset-failed >/dev/null 2>&1 || true

info "Removing SELinux module"
semodule -r steamos_manager_tracefs >/dev/null 2>&1 || info "  (not loaded)"

warn "NOT reverting /usr/share/steamos-manager/platform.toml - it is package-owned;"
warn "reinstall steamos-manager to restore it, or remove the [session] block by hand."

if [[ -n "$RESTORE_DM" ]]; then
	info "Restoring display manager: $RESTORE_DM"
	systemctl disable sddm.service >/dev/null 2>&1 || true
	systemctl enable "${RESTORE_DM}.service"
else
	warn "Display manager left as-is. If SDDM is still enabled and you want your"
	warn "old one back, re-run with --restore-dm plasmalogin (or gdm, etc)."
fi

if (( PURGE )); then
	info "Removing packages and Terra pin"
	dnf5 remove -y gamescope-session gamescope-session-steam steamos-manager \
		steamos-manager-gamescope-session-plus powerbuttond steam-notif-daemon || true
	dnf5 config-manager unsetopt terra.includepkgs terra.priority || true
	warn "terra-release left installed. Remove with: dnf5 remove terra-release"
fi

echo
info "Done. Reboot recommended."
