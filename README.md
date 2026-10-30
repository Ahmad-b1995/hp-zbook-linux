# hp-zbook-linux

Fixes for the HP ZBook 17 G3 (board 80D6) on Ubuntu, found by testing every device on one
machine and reading HP's own Windows drivers. The fixes are also sent to the kernel, so they
should reach every distribution in time; until then, `fixes/` rebuilds them for each new
Ubuntu kernel.

| What | Without this | With this | Upstream |
| --- | --- | --- | --- |
| Speaker-mute and mic-mute LEDs | never light | follow mute (codec GPIO0 and GPIO1) | [patch v2](https://lore.kernel.org/all/20261030045626.1608040-1-ahmad.b1995@gmail.com/) sent to ALSA |
| Airplane mode LED on the wireless button | stays white or amber | white with radios on, amber in airplane mode, kept across suspend | [patch](https://lore.kernel.org/all/20261030051839.1625859-1-ahmad.b1995@gmail.com/) sent to platform/x86 |
| Touchpad on/off LED and double tap in the top-left corner | no gesture, LED never lights | double tap turns the touchpad off/on through GNOME's own setting; the LED follows it (also when switched in Settings) and survives suspend | [patch](https://lore.kernel.org/all/20261030070821.1716595-1-ahmad.b1995@gmail.com/) sent to input (Synaptics driver, LED on RMI function F30 over PS/2) |
| Fan speed and temperatures | not shown | CPU and GPU fan RPM and five temperatures in `sensors` (hp-wmi-sensors, loaded at boot) | the driver exists; autoloading is deliberately off upstream |
| Boot warning `hp-wmi: Failed to apply initial fan settings: -22` and a `pwm1_enable` that cannot be written | present on Ubuntu 26.04's 7.0 kernels | gone | fixed in mainline by e931e54edb0f; Ubuntu has not picked it up |

Other ZBook 15/17 G3 and EliteBook/ProBook models of the same generation probably need the same
changes; the LED quirk is keyed to this board (PCI SSID 103c:80d6), the other fixes are not.

## Install (Ubuntu)

    sudo apt install build-essential curl patch python3
    git clone https://github.com/Ahmad-b1995/hp-zbook-linux.git
    sudo bash hp-zbook-linux/fixes/install.sh

Then reboot. `install.sh` also installs `zbook-touchpad-corner` (a small user service for the
corner double tap, `touchpad/`) and a udev rule that lets the logged-in user read the touchpad
and set its LED. It builds the fixes for every installed kernel and adds hooks to
`/etc/kernel/` so every new kernel gets them too. For each fix it downloads Ubuntu's own source
of that driver for exactly that kernel from git.launchpad.net, applies the change and builds it;
when Ubuntu's source already contains the fix (after the patches are merged), that fix is
skipped and Ubuntu's driver is used. A failure only skips that fix and never blocks a kernel
update. The log is `/var/log/zbook-fixes.log`; `fixes/uninstall.sh` removes everything.

## What does not work, and why

- **Keyboard backlight control.** Fn+F3 is handled inside the embedded controller: there is no
  ACPI method or WMI command for it and no EC register follows it, so the operating system
  cannot see or set it. It works on its own; only software control is missing.
- **Touchpad over SMBus** (`psmouse.synaptics_intertouch=1`) works, but then the touchpad no
  longer wakes the keyboard backlight, so it is left on PS/2 (`notes/touchpad-smbus-withdrawn.md`).

## How it was found

- `notes/windows-drivers.md`: what HP's Windows drivers do (Conexant/MicTray GPIOs, the
  Wireless Button Driver decompiled with Ghidra, and more).
- `scripts/`: the investigation and test scripts that were run on the laptop (ACPI and EC
  dumps, hotkey logging, LED searches, suspend tests). They are kept as a record and for
  checking other models; the fixes themselves are in `fixes/`.
- `patches/`: the patches as sent upstream, and `superseded/` for earlier versions.

Parts of this work (reading ACPI tables and HP's drivers, writing scripts and patches) were done
with an AI coding assistant (Claude); every result was checked on the machine.

## License

GPL-2.0 (`LICENSE`), as the fixes are derived from Linux kernel code.
