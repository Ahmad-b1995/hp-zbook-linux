#!/bin/bash
# Installs the corrected audio fix for the HP ZBook 17 G3 (speaker-mute LED on codec GPIO0,
# mic-mute LED on GPIO1, the existing CXT_FIXUP_MUTE_LED_GPIO) for the running kernel and checks
# both LEDs. Audio stops for a few seconds while the driver reloads.
#
#   sudo bash ~/Projects/hp-zbook-linux/scripts/update-audio-fix.sh
set -uo pipefail
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] || { echo "run with sudo from your own account" >&2; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KVER="$(uname -r)"
KO="$ROOT/build/cx/snd-hda-codec-conexant.ko"
DEST="/lib/modules/$KVER/updates/zbook"
HDA_PCI=0000:00:1f.3
OUT="$ROOT/data/$(date +%Y%m%d-%H%M%S)-audio-v2"
mkdir -p "$OUT"
trap 'chown -R "$SUDO_USER:" "$ROOT/data"' EXIT
note() { echo "$*" >> "$OUT/answers.txt"; }
ask() { read -rp "$1 " REPLY_A; note "$1 => $REPLY_A"; }
as_user() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" "$@"; }

[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KVER" ] || { echo "module was built for another kernel" >&2; exit 1; }
install -d "$DEST"
install -m 0644 "$KO" "$DEST/"
depmod "$KVER"

as_user systemctl --user stop pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse 2>/dev/null
sleep 1
echo "$HDA_PCI" > /sys/bus/pci/drivers/snd_hda_intel/unbind
modprobe -r snd_hda_codec_conexant 2>/dev/null
echo "$HDA_PCI" > /sys/bus/pci/drivers/snd_hda_intel/bind
sleep 3
as_user systemctl --user start pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse 2>/dev/null
sleep 2

ls /sys/class/leds | grep hda | tee -a "$OUT/answers.txt"
for l in /sys/class/leds/hda::*; do note "$(basename "$l") trigger: $(tr ' ' '\n' < "$l/trigger" | grep '\[')"; done
echo "Play some sound, then press the speaker-mute key a few times."
ask "Does the speaker-mute LED follow mute, and does sound still play? (y/n):"
echo "Now press Fn+F10 a few times (mic mute), and check with GNOME's mic indicator that it really mutes."
ask "Does the mic-mute LED light when the mic is muted and go off when unmuted? (y/n):"
ask "Does the microphone still record when unmuted? (y/n/not sure):"
echo "Results are in $OUT"
