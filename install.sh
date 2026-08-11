#!/usr/bin/env bash
# Build/install the GETAC MPMD ACPI driver via DKMS, grant the active seat
# user access to the resulting input device, and wire the P2 programmable
# button to launch a screenshot tool via a per-user systemd service.
#
# Usage: sudo ./install.sh [--user NAME] [--screenshot-cmd "spectacle -r"]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODVER="1.0"
SCREENSHOT_CMD="spectacle"
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--user)
		TARGET_USER="$2"
		shift 2
		;;
	--screenshot-cmd)
		SCREENSHOT_CMD="$2"
		shift 2
		;;
	-h | --help)
		echo "Usage: sudo $0 [--user NAME] [--screenshot-cmd \"spectacle -r\"]"
		exit 0
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
if [[ -z "$TARGET_USER" ]] || ! id "$TARGET_USER" &>/dev/null; then
	echo "Could not determine the desktop user; pass --user NAME" >&2
	exit 1
fi
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "==> Target user: $TARGET_USER   Screenshot command: $SCREENSHOT_CMD"

echo "==> Installing build dependencies (dkms, matching kernel headers)"
apt-get update -qq
apt-get install -y -qq dkms "linux-headers-$(uname -r)" >/dev/null

SRC_DIR="/usr/src/getac-mpmd-${MODVER}"
echo "==> Staging DKMS source in $SRC_DIR"
mkdir -p "$SRC_DIR"
cp "$REPO_DIR/getac-mpmd.c" "$REPO_DIR/Makefile" "$REPO_DIR/dkms.conf" "$SRC_DIR/"

if dkms status -m getac-mpmd -v "$MODVER" 2>/dev/null | grep -q .; then
	echo "==> Removing previous getac-mpmd DKMS registration"
	dkms remove -m getac-mpmd -v "$MODVER" --all || true
fi

echo "==> Building and installing the module via DKMS"
dkms add -m getac-mpmd -v "$MODVER"
dkms build -m getac-mpmd -v "$MODVER"
dkms install -m getac-mpmd -v "$MODVER"

echo "==> Loading module"
modprobe -r getac_mpmd 2>/dev/null || true
modprobe getac_mpmd

echo "==> Enabling module at boot"
echo "getac_mpmd" >/etc/modules-load.d/getac-mpmd.conf

echo "==> Installing udev uaccess rule for the P2 input device"
install -Dm644 "$REPO_DIR/udev/71-getac-mpmd-uaccess.rules" /etc/udev/rules.d/71-getac-mpmd-uaccess.rules
udevadm control --reload
udevadm trigger --subsystem-match=input --action=change

echo "==> Installing P2 handler to $TARGET_HOME/.local/bin/p2handler.py"
install -Dm755 "$REPO_DIR/p2handler.py" "$TARGET_HOME/.local/bin/p2handler.py"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/bin/p2handler.py"

echo "==> Installing systemd user service"
UNIT_DIR="$TARGET_HOME/.config/systemd/user"
install -Dm644 "$REPO_DIR/systemd/getac-p2handler.service" "$UNIT_DIR/getac-p2handler.service"
sed -i "s#^Environment=P2_COMMAND=.*#Environment=P2_COMMAND=$SCREENSHOT_CMD#" "$UNIT_DIR/getac-p2handler.service"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/systemd"

echo "==> Enabling P2 handler service for $TARGET_USER"
sudo -u "$TARGET_USER" \
	XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
	DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
	systemctl --user daemon-reload
sudo -u "$TARGET_USER" \
	XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
	DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
	systemctl --user enable --now getac-p2handler.service

cat <<EOF

==> Done. Press P2 to launch: $SCREENSHOT_CMD

If nothing happens, your model's ACPI notify code may not be mapped yet.
Run 'dmesg | grep getac_mpmd' after pressing P2 and look for a line like:
  getac_mpmd MTC0303:00: unknown notify event 0xNN
Add { KE_KEY, 0xNN, { KEY_PROG1 } } to getac_mpmd_keymap in getac-mpmd.c
and re-run this script.
EOF
