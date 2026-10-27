#!/bin/zsh
# KleanTalk 제거: 빈 광고 서버·인증서 신뢰·키·전용 주소를 지우고, /etc/hosts의 광고 차단 블록을 뺀다.
# 실행: KleanTalk 앱의 '제거' 버튼, 또는  sudo ./scripts/uninstall-adserver.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "sudo로 실행하세요: sudo $0"; exit 1; }

LABEL=com.myungchul.kleantalk.adserver
DIR="/Library/Application Support/KleanTalk/AdServer"
ADDR=127.84.11.1

launchctl bootout system/$LABEL 2>/dev/null || true
rm -f /Library/LaunchDaemons/$LABEL.plist
if [[ -f $DIR/cert.pem ]]; then
  FP=$(/usr/bin/openssl x509 -in "$DIR/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
  security delete-certificate -Z "$FP" /Library/Keychains/System.keychain 2>/dev/null || true
fi
rm -rf "${DIR:?}"
rmdir "/Library/Application Support/KleanTalk" 2>/dev/null || true
/sbin/ifconfig lo0 -alias $ADDR 2>/dev/null || true

# hosts에서 광고 차단 블록(# >>> KakaoAdBlock ... # <<< KakaoAdBlock)을 통째로 뺀다
awk '
  /^# >>> KakaoAdBlock/ { inside = 1; next }
  inside && /^# <<< KakaoAdBlock/ { inside = 0; next }
  !inside { print }
' /etc/hosts > /etc/hosts.kleantalk.tmp && cat /etc/hosts.kleantalk.tmp > /etc/hosts && rm -f /etc/hosts.kleantalk.tmp
dscacheutil -flushcache; killall mDNSResponder 2>/dev/null || true

echo "KleanTalk의 광고 차단과 빈 광고 서버를 모두 지웠습니다."
