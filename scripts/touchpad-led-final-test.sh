#!/bin/bash
# Tests the touchpad on/off LED and the corner double tap end to end, then installs everything
# permanently (fixes/install.sh, which also rebuilds the fixes for every installed kernel and
# takes a few minutes). The laptop sleeps once; wake it with the power button.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/touchpad-led-final-test.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KVER="$(uname -r)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-touchpad-led-final"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$(date +%T) $*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
as_user() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" \
	DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" "$@"; }
LED="/sys/class/leds/synaptics::touchpad_disabled"
since="$(date '+%F %T')"

echo "=== 1/4 patched touchpad driver"
KO="$ROOT/build/psmouse/psmouse.ko"
[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KVER" ] || { echo "psmouse.ko was built for another kernel" >&2; exit 1; }
install -d "/lib/modules/$KVER/updates/zbook"
install -m 0644 "$KO" "/lib/modules/$KVER/updates/zbook/psmouse.ko"
depmod "$KVER"
modprobe -r psmouse && modprobe psmouse
sleep 4
journalctl -k --since "$since" -o cat | grep -iE "synaptics|psmouse" | tee -a "$OUT/answers.txt"
[ -d "$LED" ] || { echo "$LED did not appear"; note "no LED"; exit 1; }

echo 1 > "$LED/brightness"; sleep 1
ask "LED ON now, and does the touchpad still move the pointer? (y/n):"
echo 0 > "$LED/brightness"; sleep 1
ask "LED OFF now, and the touchpad still works? (y/n):"

echo "=== 2/4 installing everything permanently (rebuilds for every kernel, a few minutes)"
bash "$ROOT/fixes/install.sh" | tail -3
as_user systemctl --user daemon-reload
as_user systemctl --user restart zbook-touchpad-corner.service
sleep 2
as_user systemctl --user --no-pager status zbook-touchpad-corner.service | head -6 | tee -a "$OUT/answers.txt"

echo "=== 3/4 corner double tap"
echo "Double tap the top left corner of the touchpad (two quick taps, about 1.5 cm from the corner)."
ask "Is the touchpad off (pointer does not move) and its LED on? (y/n):"
echo "Double tap the corner again."
ask "Is the touchpad back on and the LED off? (y/n):"
echo "Now turn the touchpad off in GNOME Settings (Mouse & Touchpad), then come back."
ask "Did the LED come on? (y/n):"
echo "Turn it back on in Settings."
ask "LED off again? (y/n):"

echo "=== 4/4 suspend with the touchpad off"
echo "Double tap the corner so the touchpad is off and the LED on. The laptop then sleeps;"
echo "wake it with the power button and come back."
read -rp "Press Enter when the LED is on. " _
sleep 2; systemctl suspend; sleep 10
ask "After waking: is the LED still on and the touchpad still off? (y/n):"
echo "Double tap the corner to turn it back on."
ask "Touchpad works and LED off? (y/n):"
journalctl -k --since "$since" -o cat | grep -iE "synaptics|psmouse" | tail -5 >> "$OUT/answers.txt"
as_user journalctl --user -u zbook-touchpad-corner --since "$since" --no-pager | tail -5 >> "$OUT/answers.txt"
echo "Results are in $OUT"
