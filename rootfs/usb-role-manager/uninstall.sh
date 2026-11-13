#!/bin/sh
sed -i '/usb-role-manager/d' /etc/crontabs/root 2>/dev/null
rm -f /etc/local.d/usb-role-boot.start /usr/local/bin/usb-role
echo "uninstalled (state kept in /opt/usb-role-manager/state)"
