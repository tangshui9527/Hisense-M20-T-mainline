#!/bin/sh
urldecode() { : "${1//+/ }"; printf "%b" "${_//%/\\x}"; }
len=${CONTENT_LENGTH:-999}
body=$(head -c $len)
ssid=$(urldecode "$(echo "$body" | sed -n 's/^.*ssid=\([^&]*\).*$/\1/p')")
pass=$(urldecode "$(echo "$body" | sed -n 's/^.*pass=\([^&]*\)$/\1/p')")
echo "Content-Type: text/html; charset=utf-8"
echo ""
if [ -z "$ssid" ]; then
  echo "<meta charset=utf-8>SSID 为空，<a href=/>返回</a>"; exit 0
fi
CONF=/etc/wpa_supplicant/wpa_supplicant.conf
wpa_passphrase "$ssid" "$pass" > /tmp/netblock 2>/dev/null
awk -v rmssid="$ssid" '
  /^network={/{inblk=1; buf=$0; next}
  inblk { buf=buf "\n" $0; if(/}/{ if(buf ~ rmssid) buf=""; print buf; inblk=0 } next }
  { print }
' $CONF > /tmp/wpaclean 2>/dev/null
cat /tmp/wpaclean /tmp/netblock > $CONF
touch /tmp/newwifi
echo "<meta charset=utf-8><body style=font-family:sans-serif><h2>已保存</h2><p>正在连接 <b>$ssid</b>…热点即将关闭，设备连上新网络后即可访问。</p>"
