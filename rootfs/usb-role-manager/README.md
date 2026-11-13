# usb-role-manager — M20-T USB 双角色管理

机制：chipidea 控制器原生 role switch（DTB usb-role-switch 属性 + CONFIG_USB_ROLE_SWITCH），
切换接口 = /sys/class/usb_role/ci_hdrc.0-role-switch/role（host/device 可写）。
不依赖 systemd；定时 = busybox crond；并发 = flock。

## 命令
  usb-role host|device   手动切换（持续到下一个 00:00/06:00 边界）
  usb-role auto          立即恢复按时间表调度
  usb-role status        当前角色/模式/下次切换/结果

## 时间表（本地时间）
  00:00-06:00  device（gadget：串口+网络+HID 键盘）
  06:00-24:00  host（USB 主机：U盘/手机网络共享/USB 设备）

## 文件
  schedule-apply   按当前时间应用角色（cron 00:00/06:00 + 开机调用）
  schedule-check   每 5 分钟复查：时间跳变纠正、手动到期恢复
  state/           mode、expires、last_role、last_result、schedule.log

## 限制
  - Host 模式无 VBUS 输出（无电池）：外接设备需自供电或经带供电的 OTG hub
  - 手动切换会被下一个 00:00/06:00 的 cron 覆盖（符合规格）
