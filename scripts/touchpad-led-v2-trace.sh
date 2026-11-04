#!/bin/bash
# Traces what the v2 touchpad LED code does when the LED is switched on and off: whether its
# work item runs, whether it gets to deactivate the touchpad, and which PS/2 commands fail.
# Changes nothing permanently. Takes about 10 seconds; do not touch the touchpad meanwhile.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/touchpad-led-v2-trace.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-touchpad-led-trace"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
LED="/sys/class/leds/synaptics::touchpad_disabled"
T=/sys/kernel/tracing
[ -d "$T/events" ] || mount -t tracefs nodev "$T"

{
	uname -r
	cat /sys/module/psmouse/srcversion
	ls -l "$LED/" 2>&1 | head -3
	echo "trigger: $(cat "$LED/trigger" 2>&1 | tr ' ' '\n' | grep '\[')"
} > "$OUT/info.txt"

echo 0 > "$T/tracing_on"
echo nop > "$T/current_tracer"
echo > "$T/trace"
echo > "$T/set_ftrace_filter"
for f in synaptics_rmi_led_work synaptics_rmi_led_set __synaptics_rmi_led_set synaptics_rmi_write \
	synaptics_rmi_read synaptics_mode_cmd psmouse_deactivate psmouse_activate \
	psmouse_set_state ps2_command; do
	grep -qw "$f" "$T/available_filter_functions" && echo "$f" >> "$T/set_ftrace_filter" \
		|| echo "not traceable: $f" >> "$OUT/info.txt"
done
echo > "$T/kprobe_events"
echo 'r:zb_ps2 ps2_command ret=$retval' >> "$T/kprobe_events" 2>>"$OUT/info.txt"
echo 'p:zb_state psmouse_set_state state=$arg2' >> "$T/kprobe_events" 2>>"$OUT/info.txt"
for e in zb_ps2 zb_state; do
	[ -d "$T/events/kprobes/$e" ] && echo 1 > "$T/events/kprobes/$e/enable"
done
grep -q . "$T/set_ftrace_filter" && echo function > "$T/current_tracer"
echo 1 > "$T/tracing_on"

echo "Switching the LED on, then off. Watch the touchpad's LED."
echo 1 > "$LED/brightness"; sleep 3
read -rp "Did the LED come on? (y/n) " a1
echo 0 > "$LED/brightness"; sleep 3

echo 0 > "$T/tracing_on"
grep -vE "^#" "$T/trace" | head -600 > "$OUT/trace.txt"
grep -B1 -A1 "synaptics_rmi_led_work" "$T/trace" | head -60 > "$OUT/work.txt"
echo "LED came on: $a1" >> "$OUT/info.txt"
echo nop > "$T/current_tracer"
echo > "$T/set_ftrace_filter"
for e in zb_ps2 zb_state; do
	[ -d "$T/events/kprobes/$e" ] && echo 0 > "$T/events/kprobes/$e/enable"
done
echo > "$T/kprobe_events"
echo > "$T/trace"
journalctl -k -b -o cat | grep -iE "synaptics|psmouse|led" | tail -10 >> "$OUT/info.txt"
echo "Results are in $OUT"
