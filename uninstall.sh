#!/usr/bin/env bash
# Reverse everything install.sh does.
#
# Usage: sudo ./uninstall.sh [--user NAME]
set -euo pipefail

MODVER="1.0"
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--user)
		TARGET_USER="$2"
		shift 2
		;;
	*)
		echo "Unknown argument: $1" >&2
		exit 1
		;;
	esac
done

if [[ $EUID -ne 0 ]]; then
	echo "Run as root: sudo $0" >&2
	exit 1
fi

if [[ -z "$TARGET_USER" ]]; then
	TARGET_USER="$(who | awk 'NR==1{print $1}')"
fi
if [[ -n "$TARGET_USER" ]] && id "$TARGET_USER" &>/dev/null; then
	TARGET_UID="$(id -u "$TARGET_USER")"
	TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

	echo "==> Disabling P2 handler service for $TARGET_USER"
	sudo -u "$TARGET_USER" \
		XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
		systemctl --user disable --now getac-p2handler.service 2>/dev/null || true
	rm -f "$TARGET_HOME/.config/systemd/user/getac-p2handler.service"
	rm -f "$TARGET_HOME/.local/bin/p2handler.py"
else
	echo "==> No target user found; skipping per-user service/handler cleanup" >&2
fi

echo "==> Removing udev rule"
rm -f /etc/udev/rules.d/71-getac-mpmd-uaccess.rules
udevadm control --reload
udevadm trigger --subsystem-match=input --action=change

echo "==> Unloading module"
modprobe -r getac_mpmd 2>/dev/null || true
rm -f /etc/modules-load.d/getac-mpmd.conf

echo "==> Removing DKMS registration"
dkms remove -m getac-mpmd -v "$MODVER" --all 2>/dev/null || true
rm -rf "/usr/src/getac-mpmd-${MODVER}"

echo "==> Done."
