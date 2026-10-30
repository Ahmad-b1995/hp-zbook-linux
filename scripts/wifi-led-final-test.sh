#!/bin/bash
# Installs the upstream version of the wireless-hotkey airplane mode LED patch (build/whk-up)
# for the running kernel and checks it: at load, with the button, with rfkill, and across a
# suspend. The laptop goes to sleep once during the test; wake it with the power button.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/wifi-led-final-test.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KVER="$(uname -r)"
KO="$ROOT/build/whk-up/wireless-hotkey.ko"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-wifi-led-final"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$(date +%T) $*" >> "$OUT/answers.txt"; }
colour() { local a; read -rp "  $1: wireless button light? (w = white, a = amber/red, o = off, ? = other) " a; note "$1 => $a"; }

[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KVER" ] || { echo "module was built for another kernel" >&2; exit 1; }
install -d "/lib/modules/$KVER/updates/zbook"
install -m 0644 "$KO" "/lib/modules/$KVER/updates/zbook/wireless-hotkey.ko"
depmod "$KVER"
rfkill unblock all; sleep 1
modprobe -r wireless_hotkey; modprobe wireless_hotkey; sleep 2
LED=/sys/class/leds/platform::wlan
[ -d "$LED" ] || { echo "platform::wlan missing"; note "no LED"; exit 1; }
note "trigger: $(tr ' ' '\n' < "$LED/trigger" | grep '\[')"

colour "1 right after loading (radios on)"
echo "Press the wireless button once (airplane mode on), wait 3 seconds."
colour "2 airplane on"
echo "Press it again (airplane mode off), wait 3 seconds."
colour "3 airplane off"
rfkill block all; sleep 2; colour "4 rfkill block all"
rfkill unblock all; sleep 2; colour "5 rfkill unblock all"

echo "The laptop will now sleep. Wake it with the power button, then come back here."
sleep 3; systemctl suspend; sleep 8
colour "6 after waking (radios on)"
echo "Press the wireless button once (airplane mode on), wait 3 seconds."
colour "7 airplane on"
echo "The laptop will sleep again in airplane mode. Wake it and come back."
sleep 3; systemctl suspend; sleep 8
colour "8 after waking (airplane mode)"
echo "Press the wireless button once more (airplane mode off), wait 3 seconds."
colour "9 airplane off"
journalctl -k -b -o short-precise | grep -iE "wireless.hotkey|platform::wlan" | tail -5 >> "$OUT/answers.txt"
echo "Results are in $OUT"
