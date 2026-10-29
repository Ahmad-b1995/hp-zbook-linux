#!/bin/bash
# Installs and tests the HP ZBook 17 G3 fixes built in build/ for the running kernel:
#   - hp-wmi-sensors loaded at boot, after hp-wmi (fan speeds and temperatures in `sensors`).
#     Upstream leaves it out of autoloading on purpose: on some HP models it would take hp-wmi's
#     event GUID and hp-wmi would fail to load. On this ZBook it registers no event handler, and
#     the softdep below loads hp-wmi first anyway.
#   - hp-wmi without the broken fan control (mainline commit e931e54, ported to 7.0)
#   - the Conexant audio driver with the speaker-mute LED quirk
# and searches the remaining codec pins for the mic-mute LED. Run it from your own terminal:
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/apply-fixes.sh          # install and test
#   sudo bash ~/Projects/hp-zbook-linux/scripts/apply-fixes.sh --undo   # back to Ubuntu's modules
#
# The modules go to /lib/modules/<kernel>/updates/zbook/, so they only apply to this kernel; a
# kernel update brings back Ubuntu's own modules until the fixes reach Ubuntu. The sensor driver
# setting lives in /etc/modules-load.d/ and /etc/modprobe.d/ and works on any kernel. Audio stops for a
# few seconds while its driver reloads. Results go to data/<date>-run3/.
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KVER="$(uname -r)"
DEST="/lib/modules/$KVER/updates/zbook"
LOADCONF=/etc/modules-load.d/zbook-hp-wmi-sensors.conf
DEPCONF=/etc/modprobe.d/zbook-hp-wmi-sensors.conf
HDA_PCI=0000:00:1f.3

as_user() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" "$@"; }
audio_stop() { as_user systemctl --user stop pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse 2>/dev/null; sleep 1; }
audio_start() { as_user systemctl --user start pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse 2>/dev/null; }
reload_audio() {
	audio_stop
	echo "$HDA_PCI" > /sys/bus/pci/drivers/snd_hda_intel/unbind
	modprobe -r snd_hda_codec_conexant 2>/dev/null
	echo "$HDA_PCI" > /sys/bus/pci/drivers/snd_hda_intel/bind
	sleep 3
	audio_start
}
reload_hp_wmi() { modprobe -r hp_wmi_sensors; modprobe -r hp_wmi && modprobe hp_wmi && modprobe hp_wmi_sensors; }

if [ "${1:-}" = --undo ]; then
	rm -rf "$DEST" "$LOADCONF" "$DEPCONF"
	depmod "$KVER"
	reload_hp_wmi
	reload_audio
	echo "Ubuntu's modules are back. hp-wmi-sensors stays loaded until the next reboot."
	exit 0
fi

OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-run3"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
step() { echo; echo "=== $*"; note "=== $*"; }
since="$(date '+%F %T')"

for ko in hpwmi/hp-wmi.ko cx/snd-hda-codec-conexant.ko; do
	v="$(modinfo -F vermagic "$ROOT/build/$ko" | cut -d' ' -f1)"
	[ "$v" = "$KVER" ] || { echo "$ko was built for $v, this kernel is $KVER; rebuild first" >&2; exit 1; }
done

step "0/4 touchpad back to PS/2 (so it wakes the keyboard light again)"
# Over SMBus the touchpad bypasses the embedded controller, which lights the
# keyboard on any PS/2 input, so touching the pad no longer woke the backlight.
rm -f /etc/modprobe.d/zbook-synaptics-intertouch.conf
modprobe -r psmouse && modprobe psmouse
sleep 3
grep -E '^N: Name=' /proc/bus/input/devices | grep -iE 'synaptics|touchpad' | tee -a "$OUT/answers.txt"
echo "Keep your hands off the keyboard and touchpad until the keyboard light goes off (about 15 s),"
echo "then touch the touchpad."
ask "Did the keyboard light come back on? (y/n):"

step "1/4 installing the patched modules for $KVER"
install -d "$DEST"
install -m 0644 "$ROOT/build/hpwmi/hp-wmi.ko" "$ROOT/build/cx/snd-hda-codec-conexant.ko" "$DEST/"
depmod "$KVER"
modinfo -n hp_wmi snd_hda_codec_conexant | tee -a "$OUT/answers.txt"

step "2/4 hp-wmi-sensors at boot, after hp-wmi"
echo hp_wmi_sensors > "$LOADCONF"
echo "softdep hp_wmi_sensors pre: hp_wmi" > "$DEPCONF"
modprobe hp_wmi_sensors
HWS="$(grep -l '^hp_wmi_sensors$' /sys/class/hwmon/hwmon*/name | xargs -r dirname)"
note "fan1 $(cat "$HWS/fan1_input" 2>&1) temp1 $(cat "$HWS/temp1_input" 2>&1)"

step "3/4 hp-wmi without the broken fan control"
reload_hp_wmi
sleep 2
journalctl -k --since "$since" -o cat | grep -iE "hp.wmi|subscribe" | tee "$OUT/hp-wmi.log"
lsmod | grep -E '^hp_wmi' | tee -a "$OUT/answers.txt"
HP="$(grep -l '^hp$' /sys/class/hwmon/hwmon*/name 2>/dev/null | xargs -r dirname)"
note "hp hwmon: ${HP:-none} files: $(ls "$HP" 2>/dev/null | tr '\n' ' ')"
echo "Press Fn+F5 and Fn+F6 (screen brightness) and the wireless button twice (on, then off)."
ask "Do they still work? (y/n):"

step "4/4 audio: speaker-mute LED, then the mic-mute LED search"
reload_audio
journalctl -k --since "$since" -o cat | grep -iE "snd_hda|conexant|cx20724|hdaudio" | tail -20 > "$OUT/audio.log"
ls /sys/class/leds | tee -a "$OUT/answers.txt" | grep -i hda
echo "Play some sound (any video), then press the speaker-mute key a few times."
ask "Does the mute LED light when muted and go off when unmuted, and does sound still play? (y/n):"
ask "Does the mic still work and does Fn+F10 still mute it? (y/n/not sure):"

CODEC=""
for c in /sys/class/sound/hwC*D*; do
	grep -q CX20724 "$c/chip_name" 2>/dev/null && CODEC="/dev/snd/$(basename "$c")"
done
if [ -n "$CODEC" ]; then
	PS="$(cat /sys/module/snd_hda_intel/parameters/power_save)"
	echo 0 > /sys/module/snd_hda_intel/parameters/power_save
	sleep 1
	echo "Four more blink tests on unused codec pins. Watch the mic-mute LED."
	blink() { # node verb on off
		local orig
		for _ in 1 2 3 4 5 6 7 8; do
			hda-verb "$CODEC" "$1" "$2" "$3" >/dev/null 2>&1; sleep 0.25
			hda-verb "$CODEC" "$1" "$2" "$4" >/dev/null 2>&1; sleep 0.25
		done
	}
	for t in "0x1d SET_EAPD_BTLENABLE 0x02 0x00 EAPD-1d" "0x22 SET_EAPD_BTLENABLE 0x02 0x00 EAPD-22" \
		"0x18 SET_PIN_WIDGET_CONTROL 0x24 0x00 VREF80-18" "0x1d SET_PIN_WIDGET_CONTROL 0x24 0x00 VREF80-1d"; do
		set -- $t
		orig="$(hda-verb "$CODEC" "$1" "${2/SET_/GET_}" 0 2>/dev/null | sed -n 's/^value = //p')"
		blink "$1" "$2" "$3" "$4"
		[ -n "$orig" ] && hda-verb "$CODEC" "$1" "$2" "$orig" >/dev/null 2>&1
		ask "$5: did the mic-mute LED blink? (y/n):"
	done
	echo "$PS" > /sys/module/snd_hda_intel/parameters/power_save
fi

step "5/5 mic-mute LED through the embedded controller"
# The firmware has an unused method, EC0.SAST, that sets bit 0 (AUDS) of EC register
# 0xE7; bit 1 there is SPKR. Set each bit for 4 seconds exactly as SAST would, then
# restore the register. Needs ec_sys with write support, removed again afterwards.
modprobe -r ec_sys 2>/dev/null
if modprobe ec_sys write_support=1; then
	IO=/sys/kernel/debug/ec/ec0/io
	ecget() { od -An -tu1 -j 231 -N1 "$IO" | tr -d ' '; }
	ecset() { printf "\\$(printf %03o "$1")" | dd of="$IO" bs=1 seek=231 count=1 conv=notrunc status=none; }
	orig="$(ecget)"
	note "EC 0xE7 before: $orig"
	for bit in 0 1; do
		ecset $(( orig | (1 << bit) )); sleep 4
		note "EC 0xE7 with bit $bit set: $(ecget)"
		ecset "$orig"
		ask "Bit $bit: did an LED change while it was set? (m = mic-mute LED, s = speaker-mute LED, n = nothing):"
	done
	note "EC 0xE7 restored: $(ecget)"
	modprobe -r ec_sys
else
	echo "ec_sys write support not available; skipped"
fi

step "done"
echo "Results are in $OUT. To go back to Ubuntu's modules: sudo bash $0 --undo"
