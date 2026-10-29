# Touchpad SMBus (SYN3040): tested, withdrawn

psmouse.synaptics_intertouch=1 works on the ZBook 17 G3 (binds as Synaptics TM2706-002 through
rmi4_smbus; motion, taps, buttons, scrolling and the pointing stick all fine), but over SMBus the
touchpad's traffic no longer passes through the embedded controller, which wakes the keyboard
backlight on any PS/2 input. With SMBus, touching the touchpad after the backlight timed out no
longer lights the keyboard. PS/2 felt the same to use, so SMBus brings nothing here and costs a
firmware feature. The patch adding SYN3040 to smbus_pnp_ids (branch zbook17g3-synaptics in
~/Projects/linux) must not be sent.
