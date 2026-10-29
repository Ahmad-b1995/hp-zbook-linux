# Sending the kernel patch

## Current: v2 (replaces v1, sent 2026-10-29)

v1 wrongly said the mic-mute LED is not on the codec. v2 is one line using the existing
CXT_FIXUP_MUTE_LED_GPIO (GPIO0 speaker, GPIO1 mic). Branch zbook17g3-conexant-mute-led-v2;
the v1 to v2 changelog is a git note and appears under the --- line.

1. Run scripts/update-audio-fix.sh first; send only if both LEDs follow mute.
2. cd ~/Projects/linux && git checkout zbook17g3-conexant-mute-led-v2 &&
   git commit --amend -s --no-edit &&
   git format-patch -v2 --notes -1 -o ~/Projects/hp-zbook-linux/patches/
3. ./scripts/checkpatch.pl ~/Projects/hp-zbook-linux/patches/v2-0001-*.patch
4. git send-email --in-reply-to='<20261029174446.1412118-1-ahmad.b1995@gmail.com>' \
     --to=tiwai@suse.com --to=perex@perex.cz \
     --cc=linux-sound@vger.kernel.org --cc=linux-kernel@vger.kernel.org \
     ~/Projects/hp-zbook-linux/patches/v2-0001-*.patch

## v1 (sent, superseded)

Kernel rules (Documentation/process/coding-assistants.rst): an AI assistant must not add
Signed-off-by and must never send a patch itself. You review it, sign it off and send it.

## Ready to send

`patches/0001-ALSA-hda-conexant-Add-mute-LED-quirk-for-HP-ZBook-17.patch`
(branch `zbook17g3-conexant-mute-led` in ~/Projects/linux, based on the sound tree's for-next)

To: Takashi Iwai <tiwai@suse.com>, Jaroslav Kysela <perex@perex.cz>
Cc: linux-sound@vger.kernel.org, linux-kernel@vger.kernel.org

## Steps

1. Read the patch and the commit message. You must be able to answer review questions on it.
2. Sign it off and regenerate the file:

       cd ~/Projects/linux
       git checkout zbook17g3-conexant-mute-led
       git commit --amend -s --no-edit
       git format-patch -1 -o ~/Projects/hp-zbook-linux/patches/

3. Check it: `./scripts/checkpatch.pl ~/Projects/hp-zbook-linux/patches/0001-ALSA-*.patch`
   (should report 0 errors, 0 warnings).
4. One-time email setup. Gmail needs an app password (Google account, Security,
   2-Step Verification, App passwords):

       sudo apt install git-email
       git config --global sendemail.smtpServer smtp.gmail.com
       git config --global sendemail.smtpServerPort 587
       git config --global sendemail.smtpEncryption tls
       git config --global sendemail.smtpUser ahmad.b1995@gmail.com

5. Send a copy to yourself first, then the real one:

       git send-email --to=ahmad.b1995@gmail.com ~/Projects/hp-zbook-linux/patches/0001-ALSA-*.patch
       git send-email --to=tiwai@suse.com --to=perex@perex.cz \
         --cc=linux-sound@vger.kernel.org --cc=linux-kernel@vger.kernel.org \
         ~/Projects/hp-zbook-linux/patches/0001-ALSA-*.patch

6. Replies come by email. Answer inline in plain text (no HTML, no top-posting).

## Withdrawn

The touchpad SMBus patch (SYN3040): it stops the touchpad waking the keyboard light.
See touchpad-smbus-withdrawn.md.
