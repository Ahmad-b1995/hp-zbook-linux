#!/bin/bash
# Mic-mute LED test through the embedded controller. The firmware has an unused method,
# EC0.SAST, that sets bit 0 (AUDS) of EC register 0xE7; bit 1 there is SPKR. This sets each
# bit for 4 seconds exactly as SAST would, asks what changed, and restores the register.
# Writing needs ec_sys with write_support=1, which the script loads and unloads again.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/micmute-ec-test.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-micmute-ec"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
echo "Make sure the microphone is NOT muted (mic-mute LED off) before starting."
ask "Ready? (Enter):"
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

echo "Results are in $OUT"
