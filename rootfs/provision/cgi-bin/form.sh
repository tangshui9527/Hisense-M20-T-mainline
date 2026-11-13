#!/bin/sh
s=$(echo "$QUERY_STRING" | sed -n 's/^s=//p')
echo "Content-Type: text/html; charset=utf-8"; echo ""
echo "<meta charset=utf-8><body style=font-family:sans-serif><form method=POST action=/cgi-bin/save>SSID:<input name=ssid value=\"$s\"><br>密码:<input name=pass type=password><br><input type=submit></form></body>"
