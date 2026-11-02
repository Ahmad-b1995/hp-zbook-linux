#!/bin/bash
# Installs the current fixes (fixes/install.sh: v2 of the touchpad LED patch, the initramfs
# update so the patched touchpad driver also loads at boot, and the LED retry in the corner
# helper), then checks the touchpad LED, the corner double tap and suspend. Takes a few
# minutes; the laptop sleeps once, wake it with the power button.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/touchpad-led-v2-test.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KVER="$(uname -r)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-touchpad-led-v2"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$(date +%T) $*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
as_user() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" \
	DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" "$@"; }
LED="/sys/class/leds/synaptics::touchpad_disabled"
since="$(date '+%F %T')"

echo "=== 1/4 installing (rebuilds the fixes for every kernel and updates the initramfs)"
bash "$ROOT/fixes/install.sh" 2>&1 | tail -4 | tee -a "$OUT/answers.txt"
lsinitramfs "/boot/initrd.img-$KVER" 2>/dev/null | grep -q "updates/zbook/psmouse.ko" \
	&& note "initramfs has the patched psmouse" || note "initramfs does NOT have the patched psmouse"
modprobe -r psmouse && modprobe psmouse
sleep 4
as_user systemctl --user daemon-reload
as_user systemctl --user restart zbook-touchpad-corner.service
journalctl -k --since "$since" -o cat | grep -iE "synaptics|psmouse" | tee -a "$OUT/answers.txt"
[ -d "$LED" ] || { echo "$LED did not appear"; note "no LED"; exit 1; }

echo "=== 2/4 LED from the command line"
echo 1 > "$LED/brightness"; sleep 1
ask "LED ON now, and does the touchpad still move the pointer? (y/n):"
echo 0 > "$LED/brightness"; sleep 1
ask "LED OFF now, and the touchpad still works? (y/n):"
for i in 1 2 3 4 5 6 7 8 9 10; do echo $((i % 2)) > "$LED/brightness"; done; sleep 1
ask "After ten quick switches the LED is OFF and the touchpad and pointing stick work? (y/n):"

echo "=== 3/4 corner double tap"
echo "Double tap the top left corner of the touchpad."
ask "Touchpad off and LED on? (y/n):"
echo "Double tap the corner again."
ask "Touchpad back on and LED off? (y/n):"

echo "=== 4/4 suspend with the touchpad off"
echo "Double tap the corner so the touchpad is off and the LED on. The laptop then sleeps;"
echo "wake it with the power button and come back."
read -rp "Press Enter when the LED is on. " _
sleep 2; systemctl suspend; sleep 10
ask "After waking: LED still on and touchpad still off? (y/n):"
echo "Double tap the corner to turn it back on."
ask "Touchpad works and LED off? (y/n):"
journalctl -k --since "$since" -o cat | grep -iE "synaptics|psmouse|led" | tail -8 >> "$OUT/answers.txt"
as_user journalctl --user -u zbook-touchpad-corner --since "$since" --no-pager | tail -5 >> "$OUT/answers.txt"
echo "Results are in $OUT"
echo "Last step: reboot, then run: ls /sys/class/leds | grep touchpad"
