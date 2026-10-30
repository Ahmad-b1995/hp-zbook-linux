#!/bin/bash
# Removes the HP ZBook 17 G3 fixes and their kernel hooks; Ubuntu's drivers are used again
# after the next reboot.
#
#   sudo bash ~/Projects/hp-zbook-linux/fixes/uninstall.sh
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
rm -f /etc/kernel/postinst.d/zz-zbook-fixes /etc/kernel/header_postinst.d/zz-zbook-fixes \
	/etc/kernel/postrm.d/zz-zbook-fixes \
	/etc/modules-load.d/zbook-hp-wmi-sensors.conf /etc/modprobe.d/zbook-hp-wmi-sensors.conf
for k in /lib/modules/*/; do
	rm -rf "$k/updates/zbook"
	depmod "$(basename "$k")"
done
rm -rf /usr/local/lib/zbook-fixes
echo "Removed. Reboot to go back to Ubuntu's drivers."
