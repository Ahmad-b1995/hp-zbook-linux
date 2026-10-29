File at: https://bugs.launchpad.net/ubuntu/+source/linux/+filebug
(or run `ubuntu-bug linux` on the laptop, which attaches the logs). Needs a Launchpad account.

Title: hp-wmi: "Failed to apply initial fan settings: -22" and a pwm1_enable that cannot be written on HP business laptops; please backport e931e54edb0f

Body:

On an HP ZBook 17 G3 (board 80D6, BIOS N81 01.62) running 26.04 with
linux 7.0.0-38.38-generic, hp-wmi logs at every boot:

    hp-wmi hp-wmi: Failed to apply initial fan settings: -22

and registers an "hp" hwmon device whose only attribute, pwm1_enable, cannot
be written (`echo 0 > pwm1_enable` returns EINVAL). The firmware has no fan
methods for command type 0x20008 (HPWMI_GM): the DSDT's WMI dispatcher only
handles command types 1, 2 and 0x20006, so the fan count query fails.

Ubuntu carries the April 2026 change that added the warning (7265b57fbc32,
"platform/x86: hp-wmi: fix ignored return values in fan settings"), but not
the fix that hides fan control when the firmware reports no usable fans:

    e931e54edb0f platform/x86: hp-wmi: Disable hwmon attributes when no fans are usable
    Closes: https://bugzilla.kernel.org/show_bug.cgi?id=222138

e931e54edb0f does not apply to resolute's hp-wmi.c as is (two hunks fail
because the hwmon code is older). The attached backport keeps the same logic:
cache the fan count in hp_wmi_setup_fan_settings(), hide the fan and pwm
attributes when it is not positive, and skip the initial fan settings then.

Tested on the ZBook 17 G3 with 7.0.0-38.38-generic and the backport built as an
out-of-tree module: the boot warning is gone and hp-wmi logs
"No usable fans reported by WMI, disabling fan support"; the hp hwmon device no
longer has pwm1_enable; hotkeys (brightness) and the wireless button still work.

Attachment: ubuntu-backport-e931e54.diff (build/hpwmi/ in this project)
