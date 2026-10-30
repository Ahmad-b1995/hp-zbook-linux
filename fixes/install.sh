#!/bin/bash
# Makes the HP ZBook 17 G3 fixes permanent: installs them to /usr/local/lib/zbook-fixes, adds
# kernel hooks that rebuild them for every new Ubuntu kernel, and builds them now for every
# installed kernel. Undo with uninstall.sh.
#
#   sudo bash ~/Projects/hp-zbook-linux/fixes/install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LIB=/usr/local/lib/zbook-fixes

for need in make:build-essential gcc:build-essential curl:curl patch:patch python3:python3; do
	command -v "${need%%:*}" >/dev/null || { echo "missing ${need%%:*}: apt install ${need#*:}" >&2; exit 1; }
done

install -d "$LIB"
install -m 0755 "$SRC/rebuild.sh" "$LIB/rebuild.sh"
install -m 0644 "$SRC/hp-wmi-fan-count.diff" "$SRC/wireless-hotkey.c" "$SRC/synaptics-rmi-led.diff" "$LIB/"

# Touchpad corner double tap and LED: udev access for the logged-in user, a user service
install -m 0755 "$SRC/../touchpad/zbook-touchpad-corner" /usr/local/bin/zbook-touchpad-corner
install -m 0644 "$SRC/../touchpad/70-zbook-touchpad.rules" /etc/udev/rules.d/70-zbook-touchpad.rules
install -d /etc/systemd/user
install -m 0644 "$SRC/../touchpad/zbook-touchpad-corner.service" /etc/systemd/user/
systemctl --global enable zbook-touchpad-corner.service
udevadm control --reload
udevadm trigger --subsystem-match=input --subsystem-match=leds

# Rebuild when a kernel or its headers are installed; clean up when a kernel is removed.
for dir in postinst.d header_postinst.d; do
	install -d "/etc/kernel/$dir"
	printf '#!/bin/sh\n# HP ZBook 17 G3 fixes (%s)\n%s/rebuild.sh "$1" || true\n' "$SRC" "$LIB" > "/etc/kernel/$dir/zz-zbook-fixes"
	chmod 0755 "/etc/kernel/$dir/zz-zbook-fixes"
done
install -d /etc/kernel/postrm.d
printf '#!/bin/sh\n# HP ZBook 17 G3 fixes\n[ -n "$1" ] && rm -rf "/lib/modules/$1/updates/zbook"\nexit 0\n' > /etc/kernel/postrm.d/zz-zbook-fixes
chmod 0755 /etc/kernel/postrm.d/zz-zbook-fixes

# Fan speeds and temperatures: Ubuntu's own driver, loaded at boot after hp-wmi.
echo hp_wmi_sensors > /etc/modules-load.d/zbook-hp-wmi-sensors.conf
echo "softdep hp_wmi_sensors pre: hp_wmi" > /etc/modprobe.d/zbook-hp-wmi-sensors.conf

for k in /lib/modules/*/; do
	"$LIB/rebuild.sh" "$(basename "$k")" || true
done
echo
echo "Done. Log: /var/log/zbook-fixes.log. New kernels get the fixes automatically."
