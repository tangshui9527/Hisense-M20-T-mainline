#!/bin/sh
echo "Content-Type: text/html; charset=utf-8"
echo ""
echo "<meta charset=utf-8><body style=font-family:sans-serif><h3>周围网络</h3>"
iwlist wlan0 scan 2>/dev/null | grep 'ESSID:' | sed 's/.*ESSID:"//;s/"//' | grep -v '^$' | sort -u | while read -r s; do
  echo "<p><a href=\"/cgi-bin/form.sh?s=$s\">$s</a></p>"
done
echo "<p><a href=/>手动输入</a></p></body>"
