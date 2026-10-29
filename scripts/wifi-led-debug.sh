#!/bin/bash
# Works out who sets the wireless button light, and when: the firmware on a button press,
# Linux through WLED when the radio state changes, or both. Loads a logging build of the
# patched wireless-hotkey driver, then puts the normal patched one back.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/wifi-led-debug.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-wifi-led-debug"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$(date +%T.%N | cut -c1-12) $*" >> "$OUT/answers.txt"; }
colour() { local a; read -rp "  $1: wireless button light? (w = white, a = amber/red, o = off, ? = other) " a; note "$1 => $a"; }
since="$(date '+%F %T')"

modprobe -r wireless_hotkey
insmod "$ROOT/build/whk/wireless-hotkey-debug.ko"
sleep 1
LED=/sys/class/leds/platform::wlan
[ -d "$LED" ] || { echo "platform::wlan missing"; modprobe wireless_hotkey; exit 1; }
rfkill unblock all; sleep 2

echo "=== A: firmware alone (Linux does not touch the light)"
echo none > "$LED/trigger"
echo 1 > "$LED/brightness"; sleep 1
colour "A0 after WLED(1)"
echo "Press the wireless button once and wait 3 seconds."
colour "A1 after 1st press"
echo "Press it again and wait 3 seconds."
colour "A2 after 2nd press"
rfkill unblock all; sleep 2

echo "=== B: Linux alone (radios switched with rfkill, no button)"
echo rfkill-any > "$LED/trigger"; sleep 1
colour "B0 radios on"
rfkill block all; note "rfkill block all"; sleep 2
colour "B1 radios blocked"
rfkill unblock all; note "rfkill unblock all"; sleep 2
colour "B2 radios unblocked"

echo "=== C: both (button press, light follows radio state)"
echo "Press the wireless button once and wait 3 seconds."
colour "C1 after 1st press"
rfkill list | tee -a "$OUT/answers.txt" | grep -i blocked
echo "Press it again and wait 3 seconds."
colour "C2 after 2nd press"
rfkill list | tee -a "$OUT/answers.txt" | grep -i blocked

journalctl -k --since "$since" -o short-precise | grep -iE "wireless_hotkey|WLED|button event" > "$OUT/kernel.log"
rfkill unblock all
rmmod wireless_hotkey; modprobe wireless_hotkey
echo "Results are in $OUT"
