#!/usr/bin/bash
#
# Steam Game Mode (SteamOS-style gamescope session) on stock Fedora KDE.
# See README.md. MIT licensed; see LICENSE and NOTICE.md.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRA_PKGS=(gamescope-session gamescope-session-steam steamos-manager
            steamos-manager-gamescope-session-plus powerbuttond steam-notif-daemon)

DO_CORE=0 DO_SWITCHING=0 DO_AUTOLOGIN=0 DO_CONDITIONAL=0 ASSUME_YES=0

die()  { echo >&2 "!! $*"; exit 1; }
info() { echo ":: $*"; }
warn() { echo >&2 "** $*"; }

confirm() {
	(( ASSUME_YES )) && return 0
	read -rp "   $1 [y/N] " r
	[[ "${r,,}" == y* ]]
}

usage() {
	cat <<'USAGE'
Usage: sudo ./install.sh [options]

  --core                 Terra repo (pinned), session packages, session config.
                         Gets you a "Steam Big Picture" entry in your login
                         screen's session list. Safe, reversible, no DM changes.

  --session-switching    Everything needed for Steam's "Switch to Desktop"
                         button and the session crash-recovery fallback.
                         REPLACES YOUR DISPLAY MANAGER WITH SDDM and loads a
                         local SELinux policy module. Read the README first.

  --autologin            Boot straight into Game Mode, unconditionally.
                         Requires --session-switching (needs SDDM).

  --conditional-autologin
                         Boot into Game Mode only when an HDMI display is
                         connected, otherwise show the greeter.
                         Requires --session-switching. Mutually exclusive
                         with --autologin.

  --all                  --core --session-switching --conditional-autologin
  -y, --yes              Do not prompt.
  -h, --help             This.

With no options, --core is assumed.
USAGE
}

while (( $# )); do
	case "$1" in
		--core) DO_CORE=1 ;;
		--session-switching) DO_CORE=1; DO_SWITCHING=1 ;;
		--autologin) DO_CORE=1; DO_SWITCHING=1; DO_AUTOLOGIN=1 ;;
		--conditional-autologin) DO_CORE=1; DO_SWITCHING=1; DO_CONDITIONAL=1 ;;
		--all) DO_CORE=1; DO_SWITCHING=1; DO_CONDITIONAL=1 ;;
		-y|--yes) ASSUME_YES=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage; die "unknown option: $1" ;;
	esac
	shift
done
(( DO_CORE || DO_SWITCHING )) || DO_CORE=1
if (( DO_AUTOLOGIN && DO_CONDITIONAL )); then
	die "--autologin and --conditional-autologin are mutually exclusive"
fi

# ---------------------------------------------------------------- preflight --
(( EUID == 0 )) || die "run with sudo"
[[ -r /etc/os-release ]] || die "no /etc/os-release"
. /etc/os-release
[[ "${ID:-}" == fedora ]] || die "this targets Fedora; found ID=${ID:-unknown}"
command -v dnf5 >/dev/null || die "dnf5 not found (Fedora 41+ expected)"

TARGET_USER="${SUDO_USER:-$(id -nu 1000)}"
[[ -n "$TARGET_USER" ]] || die "cannot determine target user"
info "Fedora ${VERSION_ID}, target user: ${TARGET_USER}"

if ! rpm -q steam >/dev/null 2>&1; then
	warn "Steam is not installed. gamescope-session-steam requires it."
	warn "Enable RPM Fusion nonfree-steam and install steam first."
	confirm "Continue anyway?" || exit 1
fi

# -------------------------------------------------------------------- core --
if (( DO_CORE )); then
	info "Adding Terra repository (pinned)"
	if ! rpm -q terra-release >/dev/null 2>&1; then
		# --nogpgcheck applies only to this bootstrap: no Terra key is on the
		# system yet. terra-release pulls in terra-gpg-keys, and the repo it
		# installs uses gpgcheck=1 + repo_gpgcheck=1 from then on.
		dnf5 install -y --nogpgcheck \
			--repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
			terra-release
	else
		info "  terra-release already installed"
	fi

	# Terra carries ~3000 packages including a full Mesa stack. Pin it to only
	# what we need so it can never win an upgrade for anything else.
	info "Pinning Terra to ${#TERRA_PKGS[@]} packages"
	dnf5 config-manager setopt \
		"terra.includepkgs=$(IFS=,; echo "${TERRA_PKGS[*]}")" \
		terra.priority=99

	info "Installing session packages"
	# mangohud comes from Fedora, not Terra: its build ships /usr/bin/mangoapp,
	# which is the overlay the Steam UI toggles.
	dnf5 install -y "${TERRA_PKGS[@]}" mangohud

	info "Installing session tuning config"
	install -Dm644 "$REPO_DIR/files/etc/gamescope-session-plus/sessions.d/steam" \
		/etc/gamescope-session-plus/sessions.d/steam

	info "Wiring powerbuttond into the session"
	# steamos-powerbuttond.service ships with no [Install] section, so it cannot
	# be enabled normally. This .wants symlink runs it only inside Game Mode.
	install -d "/usr/lib/systemd/user/gamescope-session-plus@steam.service.wants"
	ln -sf /usr/lib/systemd/user/steamos-powerbuttond.service \
		"/usr/lib/systemd/user/gamescope-session-plus@steam.service.wants/"

	info "Core done. 'Steam Big Picture' should now appear in your session list."
fi

# -------------------------------------------------------- session switching --
if (( DO_SWITCHING )); then
	echo
	warn "--session-switching will:"
	warn "  1. load a local SELinux policy module (init_t -> tracefs_t)"
	warn "  2. replace your display manager with SDDM"
	warn "  3. append to a package-owned file (/usr/share/steamos-manager/platform.toml)"
	warn "Your current display manager package is NOT removed, so this is reversible."
	confirm "Proceed?" || die "aborted"

	info "Building and loading SELinux module"
	# steamos-manager's log receiver creates a tracefs instance and enables the
	# OOM mark_victim trace event. SELinux denies init_t -> tracefs_t and the
	# daemon exits with "Permission denied (os error 13)".
	for t in checkmodule semodule_package semodule; do
		command -v "$t" >/dev/null || die "$t missing (install policycoreutils-devel / policycoreutils-python-utils)"
	done
	tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
	cp "$REPO_DIR/selinux/steamos_manager_tracefs.te" "$tmp/"
	( cd "$tmp"
	  checkmodule -M -m -o steamos_manager_tracefs.mod steamos_manager_tracefs.te
	  semodule_package -o steamos_manager_tracefs.pp -m steamos_manager_tracefs.mod )
	semodule -i "$tmp/steamos_manager_tracefs.pp"

	info "Installing SDDM (display manager swap)"
	rpm -q sddm >/dev/null 2>&1 || dnf5 install -y sddm

	info "Installing SteamOS vendor marker for SDDM"
	# LOAD-BEARING: without holo.conf or steamos.conf in /usr/lib/sddm/sddm.conf.d,
	# steamos-manager does not expose SessionManagement1 at all and every
	# steamosctl session verb fails with UnknownInterface.
	install -Dm644 "$REPO_DIR/files/usr/lib/sddm/sddm.conf.d/holo.conf" \
		/usr/lib/sddm/sddm.conf.d/holo.conf

	info "Installing session-switch hook"
	install -Dm755 "$REPO_DIR/files/usr/libexec/os-session-select" \
		/usr/libexec/os-session-select

	info "Configuring steamos-manager desktop session target"
	PLATFORM=/usr/share/steamos-manager/platform.toml
	if [[ -f "$PLATFORM" ]] && ! grep -q '^\[session\]' "$PLATFORM"; then
		printf '\n[session]\ndesktop = "plasma.desktop"\n' >> "$PLATFORM"
	else
		info "  [session] block already present (or platform.toml missing)"
	fi

	info "Enabling steamos-manager"
	systemctl enable --now steamos-manager.service
	systemctl enable --global steamos-manager.service steamos-manager-session-cleanup.service

	info "Switching display manager to SDDM"
	for dm in plasmalogin gdm lightdm lxdm; do
		if systemctl is-enabled "${dm}.service" >/dev/null 2>&1; then
			info "  disabling ${dm}.service"
			systemctl disable "${dm}.service"
		fi
	done
	systemctl enable sddm.service

	# Verify the interface actually came up rather than assuming.
	sleep 2
	if runuser -u "$TARGET_USER" -- steamosctl get-valid-desktop-sessions >/dev/null 2>&1; then
		info "SessionManagement1 is live."
	else
		warn "SessionManagement1 not responding yet. This is often fine before a"
		warn "reboot (the user daemon has not restarted). Re-check afterwards with:"
		warn "  steamosctl get-valid-desktop-sessions"
	fi
fi

# --------------------------------------------------------------- autologin --
if (( DO_AUTOLOGIN )); then
	info "Enabling unconditional autologin for ${TARGET_USER}"
	install -d /etc/sddm.conf.d
	cat > /etc/sddm.conf.d/10-gamemode-autologin.conf <<INNER
# Installed by fedora-big-picture-gamemode.
# Session= and Relogin= come from /usr/lib/sddm/sddm.conf.d/holo.conf.
[Autologin]
User=${TARGET_USER}
INNER
	warn "Relogin=true means exiting the session returns you to it, not a login"
	warn "screen. To escape: Ctrl+Alt+F3, then"
	warn "  sudo rm /etc/sddm.conf.d/10-gamemode-autologin.conf && sudo systemctl restart sddm"
fi

if (( DO_CONDITIONAL )); then
	info "Installing conditional (HDMI-dependent) autologin"
	install -Dm755 "$REPO_DIR/files/usr/libexec/gamemode-autologin" \
		/usr/libexec/gamemode-autologin
	install -Dm644 "$REPO_DIR/files/etc/systemd/system/gamemode-autologin.service" \
		/etc/systemd/system/gamemode-autologin.service
	systemctl daemon-reload
	systemctl enable gamemode-autologin.service
	info "Runs before the display manager each boot and decides from HDMI state."
	warn "A TV plugged in but POWERED OFF reports disconnected. Rebooting often"
	warn "puts a TV into standby, so this can miss. Override with:"
	warn "  sudo touch /etc/gamemode-autologin.force"
fi

echo
info "Done. Reboot to test."
if (( DO_SWITCHING )); then
	info "After reboot verify: steamosctl get-valid-desktop-sessions"
fi
exit 0
