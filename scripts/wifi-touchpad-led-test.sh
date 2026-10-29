#!/bin/bash
# Tests two LEDs on the HP ZBook 17 G3 that Linux never lights:
#   1. the wireless button LED, through the firmware method WLBU.WLED that HP's Windows
#      Wireless Button Driver calls (a patched wireless-hotkey module adds platform::wlan,
#      driven by the rfkill-any trigger), and
#   2. the touchpad on/off LED, through the Synaptics PS/2 LED command (the touchpad is handed
#      to serio_raw for a moment, then back to psmouse, which resets it; your USB mouse keeps
#      working meanwhile).
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/wifi-touchpad-led-test.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KVER="$(uname -r)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-wifi-touchpad-led"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
colour() { ask "  $1: what does the wireless button light show? (w = white, a = amber/red, o = off, ? = other):"; }

echo "=== 1/2 wireless button LED"
KO="$ROOT/build/whk/wireless-hotkey.ko"
[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KVER" ] || { echo "wireless-hotkey.ko was built for another kernel" >&2; exit 1; }
modprobe -r wireless_hotkey
insmod "$KO"
sleep 1
LED=/sys/class/leds/platform::wlan
if [ -d "$LED" ]; then
	colour "now (driven by radio state)"
	echo none > "$LED/trigger"
	echo 1 > "$LED/brightness"; sleep 1; colour "WLED(1)"
	echo 0 > "$LED/brightness"; sleep 1; colour "WLED(0)"
	echo 1 > "$LED/brightness"; sleep 1; colour "WLED(1) again"
	echo rfkill-any > "$LED/trigger"
	echo "Now press the wireless button once (airplane mode on) and wait 3 seconds."
	colour "airplane mode ON"
	echo "Press it again (airplane mode off) and wait 3 seconds."
	colour "airplane mode OFF"
	ask "Keep the patched driver for this kernel? (y/n):"
	if [ "$REPLY_A" = y ]; then
		install -d "/lib/modules/$KVER/updates/zbook"
		install -m 0644 "$KO" "/lib/modules/$KVER/updates/zbook/"
		depmod "$KVER"; note "installed"
	else
		rmmod wireless_hotkey; modprobe wireless_hotkey; note "reverted"
	fi
else
	echo "platform::wlan did not appear (no WLED method?)"; note "no LED"
	rmmod wireless_hotkey; modprobe wireless_hotkey
fi

echo
echo "=== 2/2 touchpad LED (Synaptics PS/2 LED command)"
PORT=""
for s in /sys/bus/serio/devices/serio*; do
	grep -qi synaptics "$s"/input/input*/name 2>/dev/null && PORT="$s"
done
[ -n "$PORT" ] || { echo "Synaptics touchpad port not found; is it on SMBus?"; exit 0; }
note "port $PORT"
echo "The touchpad stops working until the end of this test (about a minute)."
modprobe serio_raw
echo -n serio_raw > "$PORT/drvctl"
sleep 1
RAW="$(ls /dev/serio_raw* 2>/dev/null | head -n1)"
if [ -z "$RAW" ]; then
	echo "serio_raw did not attach"; echo -n psmouse > "$PORT/drvctl"; exit 0
fi
send() { # bytes... ; prints the replies
	python3 -I - "$RAW" "$@" <<'EOF'
import os, select, sys
fd = os.open(sys.argv[1], os.O_RDWR)
out = []
for b in sys.argv[2:]:
    os.write(fd, bytes([int(b, 16)]))
    r, _, _ = select.select([fd], [], [], 0.2)
    out.append(os.read(fd, 16).hex() if r else "--")
print(" ".join(out))
EOF
}
# Synaptics "special command": E6, then the argument two bits at a time with E8, then F3 0A.
led_on()  { send e6 e8 02 e8 00 e8 02 e8 00 f3 0a; }
led_off() { send e6 e8 00 e8 01 e8 00 e8 00 f3 0a; }
note "led on replies: $(led_on)"; sleep 1
ask "Is the touchpad's LED (top-left corner) ON now? (y/n):"
note "led off replies: $(led_off)"; sleep 1
ask "Is it OFF now? (y/n):"
note "led on replies: $(led_on)"; sleep 1
ask "And ON again? (y/n):"
led_off >/dev/null
echo -n psmouse > "$PORT/drvctl"
sleep 3
grep -E '^N: Name=' /proc/bus/input/devices | grep -i synaptics | tee -a "$OUT/answers.txt"
ask "Does the touchpad work normally again? (y/n):"
echo "Results are in $OUT"
