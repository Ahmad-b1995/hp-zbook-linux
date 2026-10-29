Post at: https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/new
(needs a freedesktop GitLab account). Earlier requests: #144 (2020) and #553 (2024), both closed.

Title: Validity VFS495 (138a:003f): working open driver as a TOD module, how to upstream it?

Body:

The VFS495 swipe sensor (USB 138a:003f, in 2013-2015 HP EliteBook, ProBook and ZBook laptops)
was requested in #144 and #553. There is now a working open driver:
https://github.com/Ahmad-b1995/vfs495-driver (LGPL-2.1-or-later).

What it does today, as a TOD module loaded by Ubuntu's stock libfprint (1.94.9 and 1.95.1):

- Opens the sensor's Validity SSLv3 session, configures it, arms finger detection, captures and
  decrypts swipes, and stitches them into an image. No HP code runs.
- Enrolls and verifies through fprintd; in daily use for login, lock screen and sudo on an
  HP ZBook 17 G3 (sensor firmware 04.60.00.0104).

What would block a native libfprint driver, and where I would like your view:

1. The sensor needs setup commands and RAM firmware patches before it captures. The driver
   builds them at install time from HP's own Linux driver download (SoftPaq sp84530) using a
   recipe that holds no HP data, so nothing from HP is distributed. Is a build-time or
   first-run download from the vendor acceptable for a libfprint driver, or does that keep it
   out of tree?
2. It is an image sensor with swipe stitching; would you want it on the image-device path
   (with NBIS matching) like other swipe drivers?

I can test on one unit only. If you would consider it, I am happy to port it to the in-tree
driver structure and follow your review.
