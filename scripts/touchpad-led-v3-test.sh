#!/bin/bash
# Installs v3 of the touchpad LED driver (build/psmouse-v3, built for the running kernel) and
# tests it: the LED, the corner double tap, unloading the driver with the LED on (new in v3:
# the LED must go off), and suspend. Also installs the v3 change so new kernels get it.
# The touchpad stops for a few seconds twice; the laptop sleeps once (wake it with the power
# button).
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/touchpad-led-v3-test.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KVER="$(uname -r)"
KO="$ROOT/build/psmouse-v3/psmouse.ko"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-touchpad-led-v3"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$(date +%T) $*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
LED="/sys/class/leds/synaptics::touchpad_disabled"
since="$(date '+%F %T')"

[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KVER" ] || { echo "psmouse.ko was built for another kernel" >&2; exit 1; }

echo "=== 1/5 installing v3"
install -m 0644 "$KO" "/lib/modules/$KVER/updates/zbook/psmouse.ko"
install -m 0644 "$ROOT/fixes/synaptics-rmi-led.diff" /usr/local/lib/zbook-fixes/synaptics-rmi-led.diff
depmod "$KVER"
update-initramfs -u -k "$KVER" >/dev/null 2>&1 && note "initramfs updated" || note "initramfs update FAILED"
modprobe -r psmouse && modprobe psmouse
sleep 6
journalctl -k --since "$since" -o cat | grep -iE "synaptics|psmouse" | tee -a "$OUT/answers.txt"
[ -d "$LED" ] || { echo "$LED did not appear"; note "no LED"; exit 1; }

echo "=== 2/5 LED"
echo 1 > "$LED/brightness"; sleep 2
ask "Is the touchpad LED ON? (y/n):"
echo 0 > "$LED/brightness"; sleep 2
ask "Is it OFF now? (y/n):"
ask "Does the touchpad move the pointer? (y/n):"

echo "=== 3/5 corner double tap"
echo "Double tap the top left corner of the touchpad."
ask "Is the LED ON (and the touchpad off)? (y/n):"
echo "Double tap the corner again."
ask "Is the LED OFF (and the touchpad working)? (y/n):"

echo "=== 4/5 unloading the driver with the LED on"
echo 1 > "$LED/brightness"; sleep 2
modprobe -r psmouse; sleep 2
ask "With the driver unloaded, is the LED OFF? (y/n):"
modprobe psmouse; sleep 6
ask "Driver back: does the touchpad move the pointer? (y/n):"

echo "=== 5/5 suspend with the touchpad off"
echo "Double tap the corner so the LED is on. The laptop then sleeps; wake it with the"
echo "power button and come back."
read -rp "Press Enter when the LED is on. " _
sleep 2; systemctl suspend; sleep 10
ask "After waking: is the LED still ON? (y/n):"
echo "Double tap the corner to turn the touchpad back on."
ask "Is the LED OFF and the touchpad working? (y/n):"

journalctl -k --since "$since" -o cat | grep -iE "synaptics|psmouse|led" | tail -10 >> "$OUT/answers.txt"
echo "Results are in $OUT"
