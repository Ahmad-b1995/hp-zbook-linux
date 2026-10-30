# What HP's Windows drivers do (ZBook 17 G3)

Decompiled or read from HP's own SoftPaqs (kept in vendor/, not in git).

## Speaker and mic mute LEDs: Conexant audio (sp109031, 10.0.3690.125)
- chdrt.inf, Oem.AddReg: EnableGPIO0MuteSignal = 1 (speaker mute LED on codec GPIO0).
- MicTray.ini, section MasterMute for SUBSYS_103C80D6 / 103C80F8:
  PlaybackGPIO = 0, CaptureGPIO = 1, HotKeyMicScancode = 01 01 44 (Fn+F10).
  MicTray catches the mic-mute key and has the driver set codec GPIO1.
- Confirmed on the machine (led-hunt.sh): GPIO0 = speaker LED, GPIO1 = mic LED, active high.
- Linux: CXT_FIXUP_MUTE_LED_GPIO for 103c:80d6 (patch v2 sent 2026-10-30).

## Airplane mode LED: HP Wireless Button Driver (sp95669, 2.1.9.1, WirelessButtonDriver64.sys)
- KMDF HID minidriver under mshidkmdf for ACPI\HPQ6001.
- HID report descriptor (report ID 1): input Wireless Radio Button (Generic Desktop 0xC6),
  output Wireless Radio LED (0xC7).
- Output report handler: if byte 1 bit 7 is set, evaluates WLED(byte1 & 1) through
  IOCTL_ACPI_EVAL_METHOD (0x32c004, input signature 'AeiI'). That is its only WLED call:
  nothing at start-up or resume; Windows' radio manager sends the LED report.
- ACPI: \_SB.WLBU.WLED(x) -> SSMI(0xEA90, x). WLED(1) white, WLED(0) amber (tested).
- Linux: wireless-hotkey registers platform::wlan (rfkill-any) calling WLED, and restores it
  on resume (patch on branch wireless-hotkey-wled, not sent yet).

## Keyboard backlight
- Fn+F3 is handled inside the EC; no ACPI method, no WMI command, no EC RAM byte follows it.
  Nothing for an OS driver to do.

## Touchpad LED
- Synaptics PS/2 LED command (0x88/0x10 + rate 0x0A) is acknowledged but lights nothing.
  The Windows Synaptics driver was not decompiled (large, low value without the gesture).
