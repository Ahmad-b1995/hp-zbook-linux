#!/bin/bash
# Second collection run for the HP ZBook 17 G3 driver work (the first one copied the ACPI
# tables). Run it from your own terminal, it asks questions:
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/collect2.sh
#
# About 8 minutes. Only the built-in keyboard and HP's hotkey devices are logged, and only
# during the hotkey step. Everything it changes is put back, except the touchpad setting if you
# choose to keep it. Results go to data/<date>/.
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-run2"
mkdir -p "$OUT/ec"
BG=()
stop_bg() { for p in "${BG[@]}"; do kill "$p" 2>/dev/null; done; BG=(); }
cleanup() { stop_bg; chown -R "$SUDO_USER:" "$ROOT/data"; }
trap cleanup EXIT

note() { echo "$*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
step() { echo; echo "=== $*"; note "=== $*"; }
mark() { echo "### $* $(date +%s.%N)" | tee -a "$OUT"/keys-*.log > /dev/null; }

modprobe ec_sys
EC=/sys/kernel/debug/ec/ec0/io
ec() { cat "$EC" > "$OUT/ec/$1.bin"; }
evdev() { # device name -> /dev/input/eventN
	awk -v n="$1" '/^N: Name=/{ok = ($0 == "N: Name=\"" n "\"")} ok && /^H: Handlers=/{
		for (i = 1; i <= NF; i++) if ($i ~ /^event/) print "/dev/input/" $i}' /proc/bus/input/devices
}

journalctl -kf -n0 -o short-precise > "$OUT/kernel.log" 2>&1 & BG+=($!)

step "1/6 keyboard backlight (Fn+F3)"
echo "Press Fn+F3 until the keyboard light is OFF."
ask "Then press Enter right away:"
ec kb0
for lvl in 1 2 3 4 5; do
	ask "Press Fn+F3 ONCE, then Enter right away (type d + Enter if the light just went OFF again):"
	[ "$REPLY_A" = d ] && break
	ec "kb$lvl"
done
ec kb-final

step "2/6 hotkeys (built-in keyboard and HP hotkey devices only)"
KBG=()
for n in "AT Translated Set 2 keyboard" "HP WMI hotkeys" "Wireless hotkeys" "Video Bus"; do
	for d in $(evdev "$n"); do
		f="$OUT/keys-$(echo "$n" | tr ' /' '__')-$(basename "$d").log"
		stdbuf -oL evtest "$d" > "$f" 2>&1 & KBG+=($!)
	done
done
sleep 1
echo "For each key, press it once, then press Enter. If a key puts the laptop to sleep, wake it"
echo "and carry on. Type s + Enter to skip a key."
for k in Esc F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12; do
	mark "Fn+$k"; ask "Fn+$k:"
done
for k in "the mic-mute key" "the wireless on/off key or button" "any other special button"; do
	mark "$k"; ask "Press $k, then Enter (s to skip):"
done
mark end; sleep 1
for p in "${KBG[@]}"; do kill "$p" 2>/dev/null; done

step "3/6 HP's built-in sensor driver (hp-wmi-sensors)"
modprobe hp_wmi_sensors 2>> "$OUT/hp-wmi-sensors.txt"
sleep 2
HWS="$(grep -l '^hp_wmi_sensors$' /sys/class/hwmon/hwmon*/name 2>/dev/null | xargs -r dirname)"
if [ -n "$HWS" ]; then
	for f in "$HWS"/*_label "$HWS"/*_input "$HWS"/*_fault "$HWS"/*_alarm; do
		[ -f "$f" ] && echo "$(basename "$f") = $(cat "$f" 2>&1)"
	done > "$OUT/hp-wmi-sensors.txt"
	cat "$OUT/hp-wmi-sensors.txt"
else
	echo "hp-wmi-sensors did not register" | tee -a "$OUT/hp-wmi-sensors.txt"
fi

step "4/6 mic-mute LED search"
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

step "5/6 fan (about 2 minutes, the fan will get loud)"
FAN_HW="$(grep -l '^hp$' /sys/class/hwmon/hwmon*/name | xargs -r dirname)"
sample() { # label
	ec "fan-$1"
	{
		echo -n "$1 $(date +%s) temps: $(cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | tr '\n' ' ')"
		[ -n "$HWS" ] && echo -n " hws: $(cat "$HWS"/fan*_input 2>/dev/null | tr '\n' ' ')"
		echo
	} >> "$OUT/fan.txt"
}
sample idle
if [ -n "$FAN_HW" ]; then
	note "pwm1_enable before: $(cat "$FAN_HW/pwm1_enable")"
	if echo 0 > "$FAN_HW/pwm1_enable" 2> "$OUT/pwm-write.err"; then
		note "pwm1_enable=0 (full speed) accepted"; sleep 8; sample pwm0
		ask "Did the fan go to full speed after the write? (y/n):"
	else
		note "pwm1_enable=0 rejected: $(cat "$OUT/pwm-write.err")"
	fi
	echo 2 > "$FAN_HW/pwm1_enable" 2>/dev/null
fi
LOAD=()
for _ in $(seq "$(nproc)"); do yes > /dev/null & LOAD+=($!); done
for i in $(seq 1 20); do sleep 3; sample "load$i"; done
kill "${LOAD[@]}" 2>/dev/null
for i in $(seq 1 10); do sleep 3; sample "cool$i"; done

step "6/6 touchpad over SMBus (intertouch)"
echo "The touchpad will stop for a few seconds while its driver reloads. Your USB mouse keeps working."
modprobe -r psmouse && modprobe psmouse synaptics_intertouch=1
sleep 5
journalctl -k -n 80 -o short-precise | grep -iE "psmouse|synaptics|rmi4|smbus" > "$OUT/touchpad.log"
grep -E "^N: Name=" /proc/bus/input/devices > "$OUT/input-devices.txt"
grep -iE "synaptics|touchpad|trackpoint|stick|rmi" "$OUT/input-devices.txt"
echo "Use the touchpad and the pointing stick for 30 seconds: move, tap, click all buttons"
echo "(including the three above the touchpad), two-finger scroll, pinch, rest your palm on it."
ask "Compared with before it is: b = better, s = same, w = worse, x = broken:"
TP="$REPLY_A"
if [ "$TP" = b ] || [ "$TP" = s ]; then
	ask "Are the pointing stick and its buttons working? (y/n):"
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

step "done"
echo "Results are in $OUT"
