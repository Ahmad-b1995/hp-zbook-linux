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

## Touchpad on/off: double tap and LED (Synaptics 19.0.19.68, sp91562, SynTP.sys decompiled)
- Install section for ACPI\SYN3040: HP_GROUP49_InterTouch_Inst, so Windows runs this touchpad
  over SMBus/RMI4 (InterTouch), not PS/2.
- Gesture: done in the kernel driver SynTP.sys (zone manager). TopLeftCornerFlag = 1,
  TopLeftCornerAction = 0x20 (enable/disable device), TopLeftCornerPlugInActionID = 11.
- LED: TouchZoneEnableDisableLED = 1. The byte written is TPEnabledIlluminationPower (0x10)
  when enabled and the low byte of TPDisabledIlluminationPower (0x4188 -> 0x88) when disabled
  (FUN_140062984). The driver also forces capability bits 0x00400200 (ExtraCapabilities1Add),
  since the touchpad does not report them.
- Where it goes (FUN_140061914): the driver switches to RMI over PS/2 (mode 0x14, 0x7f), scans
  the RMI page description table from 0xEE down in steps of 6 for function 0x30 (F30,
  GPIO/LED), reads its query and control bases and writes the LED byte into F30's LED control
  register (INF: BitsToModifyForSwitchLEDViaF30Ctrl). A plain PS/2 "special command" with
  rate 0x0A is only the fallback for touchpads without RMI; on this touchpad it is ACKed but
  lights nothing (tested).
- Also: KBCNotifyConfig = 0x20 makes SynTP.sys send i8042 command 0x97 plus a state byte
  ((port + 4 if flag) << 4 | 4 or 5) to the embedded controller when the touchpad is enabled
  or disabled (FUN_14005d30c). NotificationIoPort* (a direct port write) is unused on HP.
- Linux: drivers/input/rmi4/rmi_f30.c detects RMI_F30_HAS_LED but registers no LED, and only
  works in SMBus mode, which stops the touchpad waking the keyboard backlight. Nothing in Linux
  does the corner double tap.
