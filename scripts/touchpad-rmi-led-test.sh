#!/bin/bash
# Lights the touchpad on/off LED the way HP's Windows Synaptics driver (SynTP.sys 19.0.19.68)
# does on a PS/2-attached touchpad: enter RMI mode over PS/2, find RMI function $30 (GPIO/LED)
# in the page description table, and set the LED bit in its control register.
# The touchpad is handed to serio_raw for about a minute and then back to psmouse, which resets
# it; your USB mouse keeps working meanwhile. Nothing is written except F30's LED registers and
# the RMI page select.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/touchpad-rmi-led-test.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-touchpad-rmi-led"
mkdir -p "$OUT"

PORT=""
for s in /sys/bus/serio/devices/serio*; do
	grep -qi synaptics "$s"/input/input*/name 2>/dev/null && PORT="$s"
done
[ -n "$PORT" ] || { echo "Synaptics touchpad on PS/2 not found" >&2; exit 1; }

restore() {
	echo -n psmouse > "$PORT/drvctl" 2>/dev/null
	sleep 3
	grep -E '^N: Name=' /proc/bus/input/devices | grep -i synaptics >> "$OUT/log.txt"
	chown -R "$SUDO_USER:" "$ROOT/data"
}
trap restore EXIT

modprobe serio_raw
echo -n serio_raw > "$PORT/drvctl"
sleep 1
RAW="$(ls /dev/serio_raw* 2>/dev/null | head -n1)"
[ -n "$RAW" ] || { echo "serio_raw did not attach" >&2; exit 1; }
echo "Touchpad handed to $RAW; it stops working until the end of the test."

PY="$(mktemp --suffix=.py)"
cat > "$PY" <<'EOF'
import os, select, sys, time

raw, logpath = sys.argv[1], sys.argv[2]
fd = os.open(raw, os.O_RDWR)
log = open(logpath, "a")

def note(*a):
    s = " ".join(str(x) for x in a)
    print(s); log.write(s + "\n"); log.flush()

def drain():
    while select.select([fd], [], [], 0.05)[0]:
        os.read(fd, 64)

def recv(n, timeout=0.3):
    out = b""
    end = time.time() + timeout
    while len(out) < n and time.time() < end:
        if select.select([fd], [], [], max(0, end - time.time()))[0]:
            out += os.read(fd, n - len(out))
    return out

def cmd(b, extra=0):
    """Send one byte, expect ACK 0xFA, then read `extra` response bytes."""
    os.write(fd, bytes([b]))
    ack = recv(1)
    if ack != b"\xfa":
        raise RuntimeError(f"byte {b:#04x}: got {ack.hex() or 'nothing'} instead of ACK")
    return recv(extra) if extra else b""

def special(arg, rate):
    # Synaptics special command as SynTP.sys sends it: arg two bits at a time with E8, then F3 rate.
    for shift in (6, 4, 2, 0):
        cmd(0xE8); cmd((arg >> shift) & 3)
    cmd(0xF3); cmd(rate)

def rmi_write(reg, val):
    cmd(0xE7); cmd(0xF3); cmd(reg); cmd(0xF3); cmd(val)

def rmi_read(reg):
    cmd(0xE7); cmd(0xF3); cmd(reg)
    r = cmd(0xE9, 3)
    if len(r) != 3:
        raise RuntimeError(f"read {reg:#04x}: short reply {r.hex()}")
    return r[0]

def ask(q):
    a = input(q + " ").strip().lower()
    log.write(f"{q} => {a}\n"); log.flush()
    return a

try:
    cmd(0xF5)          # stop streaming so packets do not mix with replies
    drain()
    special(0x7F, 0x14)   # enter RMI mode (SynTP.sys FUN_140061914)
    note("entered RMI mode")
    f30 = None
    for page in range(4):
        rmi_write(0xFF, page)
        a = 0xEE
        while a >= 0x0B:
            fn = rmi_read(a)
            if fn == 0:
                break
            q, c, d = rmi_read(a - 5), rmi_read(a - 3), rmi_read(a - 2)
            note(f"page {page} PDT@{a:#04x}: F{fn:02X} query {q:#04x} control {c:#04x} data {d:#04x}")
            if fn == 0x30 and f30 is None:
                f30 = (page, q, c)
            a -= 6
        if f30:
            break
    if not f30:
        note("no F30 found"); sys.exit(0)
    page, q, c = f30
    rmi_write(0xFF, page)
    q0, q1 = rmi_read(q), rmi_read(q + 1)
    has_led, has_gpio = bool(q0 & 4), bool(q0 & 8)
    note(f"F30 query0 {q0:#04x} (LED {has_led}, GPIO {has_gpio}) count {q1}")
    if not has_led:
        note("F30 reports no LED"); sys.exit(0)
    if has_gpio:
        mask_byte = rmi_read(c)
        zeros = sum(1 for i in range(q1) if not mask_byte & (1 << i))
        mask = next((1 << i for i in range(q1) if mask_byte & (1 << i)), 1)
        ctrl, bright = c + 4, c + 7 + zeros
    else:
        mask, ctrl, bright = 1, c + 1, c + 4
    note(f"LED control reg {ctrl:#04x} mask {mask:#04x}, brightness reg {bright:#04x}")
    before = rmi_read(ctrl)
    note(f"control before: {before:#04x}")

    rmi_write(bright, 0x0B)
    rmi_write(ctrl, before | mask)
    time.sleep(1)
    on = ask("Is the touchpad LED (top-left corner) ON now? (y/n):")
    rmi_write(ctrl, before & ~mask)
    time.sleep(1)
    off = ask("Is it OFF now? (y/n):")
    rmi_write(ctrl, before | mask)
    time.sleep(1)
    on2 = ask("ON again? (y/n):")
    rmi_write(ctrl, before)
    note(f"result on={on} off={off} on2={on2}")
except Exception as e:
    note("error:", e)
EOF
python3 -I "$PY" "$RAW" "$OUT/log.txt"
rm -f "$PY"
echo "Handing the touchpad back to psmouse (it resets)."
