#!/bin/bash
# Collects what the driver work on this HP ZBook 17 G3 needs: ACPI tables, WMI descriptions,
# embedded controller snapshots, hotkey events, a mic-mute LED search, a fan test, a battery
# setting test and a touchpad test. Run it from your own terminal (it asks questions):
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/collect.sh
#
# Takes about 10 minutes. Everything it changes is put back, except the touchpad setting if you
# choose to keep it. Results go to data/<date>/. The MSDM and SLIC tables (Windows product key)
# are not copied, and nothing is sent anywhere.
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"/{acpi,wmi,ec}
BG=()
cleanup() {
	for p in "${BG[@]}"; do kill "$p" 2>/dev/null; done
	chown -R "$SUDO_USER:" "$ROOT/data"
}
trap cleanup EXIT

note() { echo "$*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
step() { echo; echo "=== $*"; note "=== $*"; }
mark() { echo "### $* $(date +%s.%N)" >> "$OUT/keys.log"; }

step "1/9 installing acpica-tools and alsa-tools"
apt-get install -y acpica-tools alsa-tools >/dev/null 2>&1 || echo "install failed; continuing"

step "2/9 copying ACPI tables and WMI descriptions"
for t in /sys/firmware/acpi/tables/* /sys/firmware/acpi/tables/dynamic/*; do
	[ -f "$t" ] || continue
	n="$(basename "$t")"
	case "$n" in MSDM|SLIC) continue ;; esac
	[[ "$t" == */dynamic/* ]] && n="dyn-$n"
	cat "$t" > "$OUT/acpi/$n.dat"
done
for d in /sys/bus/wmi/devices/05901221-*; do cat "$d/bmof" > "$OUT/wmi/$(basename "$d").bmof"; done
dmidecode -t 11 > "$OUT/dmi-oem-strings.txt" 2>&1
echo "copied $(ls "$OUT/acpi" | wc -l) tables"

modprobe ec_sys
EC=/sys/kernel/debug/ec/ec0/io
ec() { cat "$EC" > "$OUT/ec/$1.bin"; }
for i in 1 2 3; do ec "idle$i"; sleep 1; done

# hotkeys and kernel messages are logged in the background for steps 3 and 4
journalctl -kf -n0 -o short-precise > "$OUT/kernel.log" 2>&1 & BG+=($!)
stdbuf -oL libinput debug-events --show-keycodes >> "$OUT/keys.log" 2>&1 & BG+=($!)
sleep 1

step "3/9 keyboard backlight (embedded controller snapshots per level)"
echo "Press Fn+F5 or Fn+F6 until the keyboard light is OFF."
ask "Then press Enter right away:"
mark kb0; ec kb0
for lvl in 1 2 3 4 5; do
	ask "Make it ONE step brighter with the Fn key, then press Enter right away (type d + Enter if it was already at full brightness):"
	[ "$REPLY_A" = d ] && break
	mark "kb$lvl"; ec "kb$lvl"
done
echo "Now press Fn+F5 or Fn+F6 until the light is OFF again."
ask "Then press Enter:"
mark kb-off-again; ec kb-off-again

step "4/9 hotkeys"
echo "For each key below, press it once, then press Enter. If a key puts the laptop to sleep,"
echo "wake it and carry on. Type s + Enter to skip a key."
for k in Esc F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12; do
	mark "Fn+$k"
	ask "Fn+$k:"
done
for k in "the mic-mute key (if it is a separate key)" "the wireless on/off key or button" "any other special button"; do
	mark "$k"
	ask "Press $k, then Enter (s to skip):"
done
mark end
sleep 1

step "5/9 mic-mute LED search"
CODEC=""
for c in /sys/class/sound/hwC*D*; do
	grep -q CX20724 "$c/chip_name" 2>/dev/null && CODEC="/dev/snd/$(basename "$c")"
done
if [ -n "$CODEC" ] && command -v hda-verb >/dev/null; then
	PS="$(cat /sys/module/snd_hda_intel/parameters/power_save)"
	echo 0 > /sys/module/snd_hda_intel/parameters/power_save
	sleep 1
	ask "Does the speaker-mute key have its own LED? (y/n):"
	echo "Each test blinks one codec pin for 4 seconds. Watch the mic-mute LED (and the speaker-mute LED if there is one)."
	for i in 0 1 2 3 4 5 6; do
		m=$((1 << i))
		hda-verb "$CODEC" 0x01 SET_GPIO_MASK "$m" >/dev/null 2>&1
		hda-verb "$CODEC" 0x01 SET_GPIO_DIRECTION "$m" >/dev/null 2>&1
		for _ in 1 2 3 4 5 6 7 8; do
			hda-verb "$CODEC" 0x01 SET_GPIO_DATA "$m" >/dev/null 2>&1; sleep 0.25
			hda-verb "$CODEC" 0x01 SET_GPIO_DATA 0 >/dev/null 2>&1; sleep 0.25
		done
		hda-verb "$CODEC" 0x01 SET_GPIO_DIRECTION 0 >/dev/null 2>&1
		hda-verb "$CODEC" 0x01 SET_GPIO_MASK 0 >/dev/null 2>&1
		ask "Pin $i: did an LED blink? (m = mic-mute LED, s = speaker-mute LED, n = nothing):"
	done
	echo "$PS" > /sys/module/snd_hda_intel/parameters/power_save
else
	echo "codec or hda-verb not found; skipped"
fi

step "6/9 fan (about 2 minutes, the fan will get loud)"
FAN_HW="$(grep -l '^hp$' /sys/class/hwmon/hwmon*/name | xargs dirname)"
sample() { # label
	ec "fan-$1"
	echo "$1 $(date +%s) $(cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | tr '\n' ' ')" >> "$OUT/fan.txt"
}
sample idle
note "pwm1_enable before: $(cat "$FAN_HW/pwm1_enable")"
if echo 0 > "$FAN_HW/pwm1_enable" 2> "$OUT/pwm-write.err"; then
	note "pwm1_enable=0 (full speed) accepted"; sleep 8; sample pwm0
	ask "Did the fan go to full speed after the write? (y/n):"
else
	note "pwm1_enable=0 rejected: $(cat "$OUT/pwm-write.err")"
fi
echo 2 > "$FAN_HW/pwm1_enable" 2>/dev/null
LOAD=()
for _ in $(seq "$(nproc)"); do yes > /dev/null & LOAD+=($!); done
for i in $(seq 1 20); do sleep 3; sample "load$i"; done
kill "${LOAD[@]}" 2>/dev/null
for i in $(seq 1 10); do sleep 3; sample "cool$i"; done

step "7/9 battery charging mode (BIOS setting, put back afterwards)"
B="/sys/class/firmware-attributes/hp-bioscfg/attributes"
ORIG="$(cat "$B/Battery Health Manager/current_value")"
note "orig: $ORIG; pending_reboot before: $(cat "$B/pending_reboot")"
ec bat-before
if echo "Maximize my battery health" > "$B/Battery Health Manager/current_value" 2> "$OUT/bat-write.err"; then
	sleep 2; ec bat-health
	note "after write: $(cat "$B/Battery Health Manager/current_value"); pending_reboot: $(cat "$B/pending_reboot")"
	echo "Maximize my battery duration" > "$B/Battery Health Manager/current_value"; sleep 2; ec bat-duration
	note "duration: $(cat "$B/Battery Health Manager/current_value"); pending_reboot: $(cat "$B/pending_reboot")"
	echo "$ORIG" > "$B/Battery Health Manager/current_value"
	note "restored: $(cat "$B/Battery Health Manager/current_value"); pending_reboot: $(cat "$B/pending_reboot")"
else
	note "write rejected: $(cat "$OUT/bat-write.err")"
fi

step "8/9 touchpad over SMBus (intertouch)"
echo "The touchpad will stop for a few seconds while its driver reloads. Your USB mouse keeps working."
mark tp-start
modprobe -r psmouse && modprobe psmouse synaptics_intertouch=1
sleep 5
journalctl -k -n 60 -o short-precise | grep -iE "psmouse|synaptics|rmi4|smbus" > "$OUT/touchpad.log"
libinput list-devices > "$OUT/libinput-devices.txt" 2>&1
grep -iE "^Device:" "$OUT/libinput-devices.txt"
echo "Use the touchpad and the pointing stick for 30 seconds: move, tap, click all buttons"
echo "(including the three above the touchpad), two-finger scroll, pinch, rest your palm on it."
ask "Compared with before it is: b = better, s = same, w = worse, x = broken:"
TP="$REPLY_A"
if [ "$TP" = b ] || [ "$TP" = s ]; then
	ask "Is the pointing stick and its buttons working? (y/n):"
	PS_OK="$REPLY_A"
	ask "Keep SMBus mode across reboots? (y/n):"
	if [ "$REPLY_A" = y ] && [ "$PS_OK" = y ]; then
		echo "options psmouse synaptics_intertouch=1" > /etc/modprobe.d/zbook-synaptics-intertouch.conf
		note "kept in /etc/modprobe.d/zbook-synaptics-intertouch.conf"
	else
		modprobe -r psmouse && modprobe psmouse; note "reverted"
	fi
else
	modprobe -r psmouse && modprobe psmouse; note "reverted"
fi

step "9/9 done"
echo "Results are in $OUT"
