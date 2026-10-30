#!/bin/bash
# Builds the HP ZBook 17 G3 kernel fixes for one Ubuntu kernel and installs them to
# /lib/modules/<kernel>/updates/zbook/. Run by the kernel install hooks, or by hand:
#
#   sudo /usr/local/lib/zbook-fixes/rebuild.sh [kernel-version]
#
# For each fix it downloads Ubuntu's own source of that driver for exactly that kernel
# (git.launchpad.net, tag Ubuntu-<package version>), applies the change and builds it. A fix
# whose change is already in Ubuntu's source is skipped, so Ubuntu's driver is used. Any
# failure only skips that fix; this script never makes a kernel install fail.
#
#   hp-wmi           hide the fan control the firmware rejects (backport of mainline e931e54)
#   conexant         speaker-mute (GPIO0) and mic-mute (GPIO1) LEDs, 103c:80d6
#   wireless-hotkey  airplane mode LED through WLBU.WLED
#   psmouse          touchpad on/off LED (RMI F30 over PS/2) for the Synaptics driver
set -uo pipefail

KVER="${1:-$(uname -r)}"
LIB="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LOG=/var/log/zbook-fixes.log
KDIR="/lib/modules/$KVER/build"
DEST="/lib/modules/$KVER/updates/zbook"

# ZBOOK_TEST=<dir>: build into <dir> as a normal user, without installing anything.
if [ -n "${ZBOOK_TEST:-}" ]; then
	DEST="$ZBOOK_TEST/$KVER"; LOG="$ZBOOK_TEST/log"
fi
log() { echo "$(date '+%F %T') [$KVER] $*" | tee -a "$LOG"; }

[ -n "${ZBOOK_TEST:-}" ] || [ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
if [ ! -f "$KDIR/Makefile" ]; then
	log "no kernel headers yet; will build when they are installed"
	exit 0
fi
PKGVER="$(dpkg-query -W -f='${Version}' "linux-image-$KVER" 2>/dev/null || dpkg-query -W -f='${Version}' "linux-image-unsigned-$KVER" 2>/dev/null)"
[ -n "$PKGVER" ] || { log "not an Ubuntu kernel package; skipped"; exit 0; }
SERIES="$(. /etc/os-release && echo "$VERSION_CODENAME")"
BASE="https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/$SERIES/plain"
TAG="Ubuntu-$PKGVER"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() { # source-path dest
	local try
	for try in 1 2 3 4; do
		curl -fsS -m 60 -o "$2" "$BASE/$1?h=$TAG" 2>/dev/null && return 0
		# Launchpad sometimes answers 500; the local proxy helps when the direct route is blocked.
		if curl -fsS -m 3 -o /dev/null -x http://127.0.0.1:10808 https://git.launchpad.net 2>/dev/null; then
			curl -fsS -m 60 -x http://127.0.0.1:10808 -o "$2" "$BASE/$1?h=$TAG" 2>/dev/null && return 0
		fi
		sleep $((try * 3))
	done
	return 1
}

build() { # name dir module-file
	if make -s -C "$KDIR" M="$2" modules >"$2/build.log" 2>&1 && [ -f "$2/$3" ]; then
		install -d "$DEST"
		install -m 0644 "$2/$3" "$DEST/$3"
		log "$1: installed"
		return 0
	fi
	log "$1: build failed (see below); Ubuntu's driver stays"
	tail -n 5 "$2/build.log" >> "$LOG"
	rm -f "$DEST/$3"
	return 1
}

skip() { # name module-file reason
	rm -f "$DEST/$2"
	log "$1: $3; Ubuntu's driver stays"
}

# --- hp-wmi
d="$WORK/hp-wmi"; mkdir -p "$d"
if ! fetch drivers/platform/x86/hp/hp-wmi.c "$d/hp-wmi.c"; then
	skip hp-wmi hp-wmi.ko "could not download its source"
elif grep -q "No usable fans reported by WMI" "$d/hp-wmi.c"; then
	skip hp-wmi hp-wmi.ko "fix already in Ubuntu's source"
elif patch -s -d "$d" hp-wmi.c < "$LIB/hp-wmi-fan-count.diff" >/dev/null 2>&1; then
	echo 'obj-m := hp-wmi.o' > "$d/Kbuild"
	build hp-wmi "$d" hp-wmi.ko
else
	skip hp-wmi hp-wmi.ko "the change no longer applies to this source"
fi

# --- conexant (needs the HDA headers that the kernel headers package does not ship)
d="$WORK/conexant"; mkdir -p "$d/inc/common" "$d/inc/codecs" "$d/helpers"
ok=1
fetch sound/hda/codecs/conexant.c "$d/conexant.c" || ok=0
for h in common/hda_local.h common/hda_auto_parser.h common/hda_beep.h common/hda_jack.h \
	common/hda_controller.h codecs/generic.h; do
	[ $ok = 1 ] && { fetch "sound/hda/$h" "$d/inc/$h" || ok=0; }
done
for h in thinkpad.c ideapad_hotkey_led.c; do
	[ $ok = 1 ] && { fetch "sound/hda/codecs/helpers/$h" "$d/helpers/$h" || ok=0; }
done
if [ $ok = 0 ]; then
	skip conexant snd-hda-codec-conexant.ko "could not download its source"
elif grep -qi 'SND_PCI_QUIRK(0x103c, 0x80d6' "$d/conexant.c"; then
	skip conexant snd-hda-codec-conexant.ko "fix already in Ubuntu's source"
elif python3 -I - "$d/conexant.c" <<'EOF'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
for i, l in enumerate(lines):
    if 'SND_PCI_QUIRK(0x103c, 0x80FD' in l or 'SND_PCI_QUIRK(0x103c, 0x8115' in l:
        lines.insert(i, '\tSND_PCI_QUIRK(0x103c, 0x80d6, "HP ZBook 17 G3", CXT_FIXUP_MUTE_LED_GPIO),')
        open(p, 'w').write('\n'.join(lines))
        sys.exit(0)
sys.exit(1)
EOF
then
	printf 'obj-m := snd-hda-codec-conexant.o\nsnd-hda-codec-conexant-y := conexant.o\nccflags-y += -I$(src)/inc/common -I$(src)/inc/codecs\n' > "$d/Kbuild"
	build conexant "$d" snd-hda-codec-conexant.ko
else
	skip conexant snd-hda-codec-conexant.ko "the quirk table changed"
fi

# --- wireless-hotkey (small and stable: ships the whole patched driver, sent upstream 2026-10-30)
d="$WORK/wireless-hotkey"; mkdir -p "$d"
if fetch drivers/platform/x86/wireless-hotkey.c "$d/ubuntu.c" && grep -q '"WLED"' "$d/ubuntu.c"; then
	skip wireless-hotkey wireless-hotkey.ko "fix already in Ubuntu's source"
else
	cp "$LIB/wireless-hotkey.c" "$d/wireless-hotkey.c"
	echo 'obj-m := wireless-hotkey.o' > "$d/Kbuild"
	build wireless-hotkey "$d" wireless-hotkey.ko
fi

# --- psmouse (synaptics.c with the touchpad LED; the module is built from all its sources)
d="$WORK/psmouse"; mkdir -p "$d"
if ! fetch drivers/input/mouse/Makefile "$d/Makefile.ubuntu"; then
	skip psmouse psmouse.ko "could not download its source"
else
	ok=1
	{ echo 'obj-m := psmouse.o'; grep -E '^psmouse' "$d/Makefile.ubuntu"; } > "$d/Kbuild"
	for o in $(grep -E '^psmouse' "$d/Makefile.ubuntu" | grep -oE '[a-z0-9_-]+\.o' | sed 's/\.o$//'); do
		fetch "drivers/input/mouse/$o.c" "$d/$o.c" || ok=0
		fetch "drivers/input/mouse/$o.h" "$d/$o.h" 2>/dev/null || rm -f "$d/$o.h"
	done
	for h in psmouse.h elan_i2c.h; do fetch "drivers/input/mouse/$h" "$d/$h" || ok=0; done
	if [ $ok = 0 ]; then
		skip psmouse psmouse.ko "could not download its source"
	elif grep -q rmi_led_pnp_ids "$d/synaptics.c"; then
		skip psmouse psmouse.ko "fix already in Ubuntu's source"
	elif patch -s -p4 -d "$d" < "$LIB/synaptics-rmi-led.diff" >/dev/null 2>&1; then
		build psmouse "$d" psmouse.ko
	else
		skip psmouse psmouse.ko "the change no longer applies to this source"
	fi
fi

[ -n "${ZBOOK_TEST:-}" ] || depmod "$KVER"
exit 0
