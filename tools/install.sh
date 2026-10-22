#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Xcfcdl <746953609@qq.com>
# Install the SOF audio / FM tools for the Xiaomi Mi Pad 2.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bindir=${BINDIR:-/usr/local/bin}
tplgdir=${TPLG_DIR:-/lib/firmware/intel/sof-tplg}

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

command -v cc >/dev/null || { echo "error: a C compiler (cc) is required" >&2; exit 1; }

install -d "$bindir" "$tplgdir" /usr/share/applications /etc/systemd/user \
	/etc/xdg/autostart

install -m 755 "$here/fm-radio" "$bindir/fm-radio"
install -m 755 "$here/fm-listen.sh" "$bindir/fm-listen.sh"
install -m 755 "$here/latte-jack-switch" "$bindir/latte-jack-switch"
install -m 644 "$here/fm-radio.desktop" /usr/share/applications/fm-radio.desktop
install -m 644 "$here/fm-radio-autostart.desktop" \
	/etc/xdg/autostart/fm-radio.desktop
install -m 644 "$here/latte-jack-switch.service" /etc/systemd/user/latte-jack-switch.service

install -m 644 "$here/../sof/sof-cht-rt5659.tplg" "$tplgdir/sof-cht-rt5659.tplg"

cc -O2 -Wall -Wextra -o "$bindir/hci_fm" "$here/hci_fm.c"
chmod 755 "$bindir/hci_fm"

for tool in python3 pactl amixer; do
	command -v "$tool" >/dev/null || echo "warning: $tool not found" >&2
done
python3 -c 'import gi' 2>/dev/null || echo "warning: python-gobject (gi) not found" >&2
python3 -c 'import gi; gi.require_version("Gtk", "3.0")' 2>/dev/null ||
	echo "warning: GTK 3 bindings not found" >&2

cat <<'EOF'

Installed:
  /usr/local/bin/{hci_fm,fm-radio,fm-listen.sh,latte-jack-switch}
  /usr/share/applications/fm-radio.desktop
  /etc/xdg/autostart/fm-radio.desktop
  /etc/systemd/user/latte-jack-switch.service
  /lib/firmware/intel/sof-tplg/sof-cht-rt5659.tplg

Still required:
  1. Kernel with the Mi Pad 2 SOF machine driver (see README.md).
  2. sof-cht.ri v2.2 at /lib/firmware/intel/sof/sof-cht.ri.
  3. Passwordless sudo for hci_fm and amixer for the desktop user.
  4. Enable the jack daemon:  systemctl --user enable --now latte-jack-switch
EOF
