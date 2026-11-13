#!/bin/sh
# install.sh — 安装 usb-role manager（在本机 root shell 执行，或从仓库目录）
set -e
BASE=/opt/usb-role-manager
mkdir -p $BASE/state
HERE=$(cd "$(dirname "$0")" && pwd)
install -m 755 $HERE/usb-role $BASE/usb-role
install -m 755 $HERE/schedule-apply $BASE/schedule-apply
install -m 755 $HERE/schedule-check $BASE/schedule-check
ln -sf $BASE/usb-role /usr/local/bin/usb-role
# cron：00:00→device，06:00→host，每 5 分钟复查（时间跳变/手动过期）
CRON=/etc/crontabs/root
touch $CRON
grep -q usb-role-manager $CRON || cat >> $CRON <<CRON
0 0 * * * /opt/usb-role-manager/schedule-apply
0 6 * * * /opt/usb-role-manager/schedule-apply
*/5 * * * * /opt/usb-role-manager/schedule-check
CRON
/etc/init.d/crond restart >/dev/null 2>&1 || /etc/init.d/crond start
# 开机即按当前时间应用角色
grep -q "usb-role schedule-apply" /etc/local.d/usb-role-boot.start 2>/dev/null || \
    printf '#!/bin/sh\n/opt/usb-role-manager/schedule-apply\n' > /etc/local.d/usb-role-boot.start
chmod +x /etc/local.d/usb-role-boot.start
echo "installed. try: usb-role status"
