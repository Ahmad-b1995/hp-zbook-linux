#!/bin/bash
# Mic-mute LED hunt for the HP ZBook 17 G3: every candidate tried so far, held still instead of
# blinked. Each test sets a state and waits until you say which LEDs are on, then sets the
# opposite state and asks again; a test counts as a hit only when the two answers differ.
#
# HP's Windows driver (MicTray, section MasterMute for this model) sets CaptureGPIO = 1 and
# PlaybackGPIO = 0, so codec GPIO1 is the expected mic-mute LED and GPIO0 the speaker-mute LED.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/led-hunt.sh
#
# Everything is restored at the end (codec GPIO, pin settings, EC register 0xE7).
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }
command -v hda-verb >/dev/null || { echo "hda-verb missing: sudo apt install alsa-tools" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-led-hunt"
mkdir -p "$OUT"
LOG="$OUT/results.txt"

CODEC=""
for c in /sys/class/sound/hwC*D*; do
	grep -q CX20724 "$c/chip_name" 2>/dev/null && CODEC="/dev/snd/$(basename "$c")"
done
[ -n "$CODEC" ] || { echo "Conexant CX20724 codec not found" >&2; exit 1; }

verb() { hda-verb "$CODEC" "$@" 2>/dev/null | sed -n 's/^value = //p'; }
PS="$(cat /sys/module/snd_hda_intel/parameters/power_save)"
echo 0 > /sys/module/snd_hda_intel/parameters/power_save
sleep 1

# Remember what the driver set, to put it back afterwards.
G_MASK="$(verb 0x01 GET_GPIO_MASK 0)"; G_DIR="$(verb 0x01 GET_GPIO_DIRECTION 0)"; G_DATA="$(verb 0x01 GET_GPIO_DATA 0)"
declare -A PINCTL EAPD
for n in 0x18 0x19 0x1d; do PINCTL[$n]="$(verb $n GET_PIN_WIDGET_CONTROL 0)"; done
for n in 0x1d 0x22; do EAPD[$n]="$(verb $n GET_EAPD_BTLENABLE 0)"; done
EC_OK=0
modprobe -r ec_sys 2>/dev/null
if modprobe ec_sys write_support=1; then
	EC_OK=1
	IO=/sys/kernel/debug/ec/ec0/io
	ecget() { od -An -tu1 -j 231 -N1 "$IO" | tr -d ' '; }
	ecset() { printf "\\$(printf %03o "$1")" | dd of="$IO" bs=1 seek=231 count=1 conv=notrunc status=none; }
	EC_ORIG="$(ecget)"
fi
echo "codec $CODEC gpio mask=$G_MASK dir=$G_DIR data=$G_DATA ec0xE7=${EC_ORIG:-n/a}" > "$LOG"

restore() {
	hda-verb "$CODEC" 0x01 SET_GPIO_MASK "$G_MASK" >/dev/null 2>&1
	hda-verb "$CODEC" 0x01 SET_GPIO_DIRECTION "$G_DIR" >/dev/null 2>&1
	hda-verb "$CODEC" 0x01 SET_GPIO_DATA "$G_DATA" >/dev/null 2>&1
	for n in "${!PINCTL[@]}"; do [ -n "${PINCTL[$n]}" ] && hda-verb "$CODEC" "$n" SET_PIN_WIDGET_CONTROL "${PINCTL[$n]}" >/dev/null 2>&1; done
	for n in "${!EAPD[@]}"; do [ -n "${EAPD[$n]}" ] && hda-verb "$CODEC" "$n" SET_EAPD_BTLENABLE "${EAPD[$n]}" >/dev/null 2>&1; done
	if [ "$EC_OK" = 1 ]; then ecset "$EC_ORIG"; modprobe -r ec_sys; fi
	echo "$PS" > /sys/module/snd_hda_intel/parameters/power_save
	chown -R "$SUDO_USER:" "$ROOT/data"
}
trap restore EXIT

look() { # label -> answer in $A
	local a
	while :; do
		read -rp "  $1: which LEDs are ON right now? (m = mic-mute, s = speaker-mute, b = both, n = none) " a
		case "$a" in m|s|b|n) break ;; esac
	done
	A="$a"
}
HITS=()
test_pair() { # name, command for state A, command for state B
	local name="$1" a b
	echo; echo "== $name"
	eval "$2"; sleep 1; look "state 1"; a="$A"
	eval "$3"; sleep 1; look "state 2"; b="$A"
	echo "$name: state1=$a state2=$b" >> "$LOG"
	if [ "$a" != "$b" ]; then
		echo "  -> CHANGED ($a -> $b)"; HITS+=("$name ($a -> $b)")
	fi
}
gpio() { # mask dir data
	hda-verb "$CODEC" 0x01 SET_GPIO_MASK "$1" >/dev/null 2>&1
	hda-verb "$CODEC" 0x01 SET_GPIO_DIRECTION "$2" >/dev/null 2>&1
	hda-verb "$CODEC" 0x01 SET_GPIO_DATA "$3" >/dev/null 2>&1
}

echo "Unmute the speakers and the microphone first, so both LEDs start off."
echo "Each step holds still; take your time looking before you answer."
read -rp "Press Enter to start. " _

# Sanity check: GPIO0 is the speaker-mute LED (confirmed). If this does not change the
# speaker LED, the answers below cannot be trusted.
test_pair "GPIO0 (known speaker LED)" "gpio 0x01 0x01 0x01" "gpio 0x01 0x01 0x00"

# HP's own setting for this model: CaptureGPIO = 1.
test_pair "GPIO1 with GPIO0 kept low" "gpio 0x03 0x03 0x02" "gpio 0x03 0x03 0x00"
test_pair "GPIO1 alone" "gpio 0x02 0x02 0x02" "gpio 0x02 0x02 0x00"
test_pair "GPIO1 alone, inverted" "gpio 0x02 0x02 0x00" "gpio 0x02 0x02 0x02"
for i in 2 3 4 5 6; do
	m=$(printf '0x%02x' $((1 << i)))
	test_pair "GPIO$i" "gpio $m $m $m" "gpio $m $m 0x00"
done
test_pair "all GPIOs 0-6" "gpio 0x7f 0x7f 0x7f" "gpio 0x7f 0x7f 0x00"
gpio "$G_MASK" "$G_DIR" "$G_DATA"

for n in 0x1d 0x22; do
	test_pair "EAPD pin $n" "hda-verb $CODEC $n SET_EAPD_BTLENABLE 0x02 >/dev/null" "hda-verb $CODEC $n SET_EAPD_BTLENABLE 0x00 >/dev/null"
done
for n in 0x18 0x19 0x1d; do
	test_pair "VREF 80% pin $n" "hda-verb $CODEC $n SET_PIN_WIDGET_CONTROL 0x24 >/dev/null" "hda-verb $CODEC $n SET_PIN_WIDGET_CONTROL 0x20 >/dev/null"
	[ -n "${PINCTL[$n]}" ] && hda-verb "$CODEC" "$n" SET_PIN_WIDGET_CONTROL "${PINCTL[$n]}" >/dev/null 2>&1
done

if [ "$EC_OK" = 1 ]; then
	test_pair "EC 0xE7 bit 0 (AUDS)" "ecset $((EC_ORIG | 1))" "ecset $EC_ORIG"
	test_pair "EC 0xE7 bit 1 (SPKR)" "ecset $((EC_ORIG | 2))" "ecset $EC_ORIG"
fi

echo
if [ "${#HITS[@]}" -gt 0 ]; then
	echo "Changes seen:"; printf '  %s\n' "${HITS[@]}" | tee -a "$LOG"
else
	echo "No test changed an LED." | tee -a "$LOG"
fi
echo "Results are in $LOG (everything is being restored now)."
