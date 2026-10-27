#!/bin/zsh
# KleanTalk 빈 광고 서버 설치 (다시 실행하면 인증서를 새로 만들어 갱신한다)
# 실행: KleanTalk 앱의 '빈 광고 서버 설치' 버튼, 또는 ./build.sh 로 빌드한 뒤  sudo ./scripts/install-adserver.sh [서버 실행 파일]
#
# 하는 일
#  1. serv.ds.kakao.com 한 이름에만 쓰는 인증서와 키를 만든다. (인증 기관이 아닌 일반 인증서, 825일)
#     키는 root만 읽을 수 있는 폴더에 둔다.
#  2. (인증서 신뢰 등록은 이 스크립트가 아니라 KleanTalk 앱이 사용자 권한으로 한다. 아래 참고)
#  3. 빈 광고 서버를 LaunchDaemon으로 등록한다. (전용 주소 127.84.11.1:443 / 포트를 연 뒤 nobody 권한으로 동작)
#  4. /etc/hosts에서 serv.ds.kakao.com을 그 전용 주소로 돌린다. 다른 광고 주소는 계속 막는다.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "sudo로 실행하세요: sudo $0"; exit 1; }

HOST=serv.ds.kakao.com
ADDR=127.84.11.1   # 서버 전용 루프백 주소 (127.0.0.1:443을 쓰는 개발 도구와 부딪치지 않게)
LABEL=com.myungchul.kleantalk.adserver
DIR="/Library/Application Support/KleanTalk/AdServer"
PLIST=/Library/LaunchDaemons/$LABEL.plist
# 서버 실행 파일: 인자로 받거나(앱 안에 든 것), 없으면 빌드 폴더의 것
SRC="${1:-${0:A:h}/../build/kleantalk-adserver}"

[[ -x $SRC ]] || { echo "먼저 ./build.sh 로 빌드하세요 ($SRC 없음)"; exit 1; }

# 이전 설치가 있으면 서버를 멈춘다
launchctl bootout system/$LABEL 2>/dev/null || true

# 지금 인증서가 30일 넘게 남아 있으면 그대로 쓴다 (다시 설치해도 인증서 신뢰를 다시 등록할 필요가 없다)
REUSE=false
if [[ -f $DIR/cert.pem && -f $DIR/key.der ]] && /usr/bin/openssl x509 -in "$DIR/cert.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
  REUSE=true
fi

# 1. 프로그램과 인증서·키
mkdir -p "$DIR"
chown root:wheel "$DIR"; chmod 755 "$DIR"
install -o root -g wheel -m 755 "$SRC" "$DIR/kleantalk-adserver"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
if [[ $REUSE == false ]]; then
/usr/bin/openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
/usr/bin/openssl req -new -x509 -key "$TMP/key.pem" -days 825 -subj "/CN=$HOST" \
  -addext "subjectAltName=DNS:$HOST" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth" \
  -out "$TMP/cert.pem" 2>/dev/null
install -o root -g wheel -m 600 /dev/null "$DIR/key.der"
/usr/bin/openssl rsa -in "$TMP/key.pem" -outform DER -out "$DIR/key.der" 2>/dev/null
install -o root -g wheel -m 644 "$TMP/cert.pem" "$DIR/cert.pem"
/usr/bin/openssl x509 -in "$DIR/cert.pem" -outform DER -out "$DIR/cert.der"
chmod 644 "$DIR/cert.der"
fi

# 2. 인증서 신뢰는 여기서 하지 않는다. 관리자 권한 스크립트 안에서는 macOS가 확인 창을 띄울 수 없어
#    신뢰 설정을 거부하기 때문이다. KleanTalk 앱이 설치 뒤 사용자 권한으로 등록한다(macOS 확인 창이 뜬다).
#    터미널로 설치할 때는 맨 끝에 안내하는 명령을 사용자 권한(sudo 없이)으로 실행한다.

# 3. LaunchDaemon
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DIR/kleantalk-adserver</string>
		<string>$DIR/cert.der</string>
		<string>$DIR/key.der</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"

# 4. hosts: serv.ds.kakao.com만 서버 전용 주소로. KleanTalk 블록이 없으면 만든다.
if ! grep -q '^# >>> KakaoAdBlock' /etc/hosts; then
  [[ -f /etc/hosts.kakaoadblock.bak ]] || cp /etc/hosts /etc/hosts.kakaoadblock.bak
  printf '\n# >>> KakaoAdBlock (managed by KleanTalk)\n0.0.0.0 display.ad.daum.net\n:: display.ad.daum.net\n0.0.0.0 analytics.ad.daum.net\n:: analytics.ad.daum.net\n0.0.0.0 %s\n:: %s\n# <<< KakaoAdBlock\n' $HOST $HOST >> /etc/hosts
fi
# 블록 안에서 serv.ds.kakao.com의 IPv4만 서버 전용 주소로, 나머지(다른 주소, 모든 IPv6)는 막음(0.0.0.0, ::)으로 맞춘다.
# IPv6가 막혀 있으면 카카오톡은 곧바로 IPv4(전용 주소)로 연결한다.
awk -v host="$HOST" -v addr="$ADDR" '
  /^# >>> KakaoAdBlock/ { inside = 1; print; next }
  /^# <<< KakaoAdBlock/ { inside = 0; print; next }
  inside && NF >= 2 && $1 ~ /^[0-9.]+$/ { print ($2 == host ? addr " " : "0.0.0.0 ") $2; next }
  inside && NF >= 2 && $1 ~ /:/ { print ":: " $2; next }
  { print }
' /etc/hosts > /etc/hosts.kleantalk.tmp && cat /etc/hosts.kleantalk.tmp > /etc/hosts && rm -f /etc/hosts.kleantalk.tmp
dscacheutil -flushcache; killall mDNSResponder 2>/dev/null || true

echo "설치했습니다. 터미널로 설치했다면 마지막으로 인증서 신뢰를 등록하세요 (sudo 없이, macOS 확인 창이 뜸):"
echo "  security add-trusted-cert -r trustRoot -p ssl -s $HOST \"$DIR/cert.pem\""
echo "그다음 카카오톡을 종료했다가 다시 열면 광고 자리가 빈 공간으로 바뀝니다."
echo "인증서 만료: $(/usr/bin/openssl x509 -in "$DIR/cert.pem" -noout -enddate | cut -d= -f2) — 그 전에 이 스크립트를 다시 실행하면 갱신됩니다."
