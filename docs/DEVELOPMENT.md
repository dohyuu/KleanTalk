# NoAdsTalk 개발 노트

구조와, 지금 방식으로 정한 이유를 정리했습니다. 바꾸기 전에 읽어 주세요.

## 구성

```
Sources/KleanTalk.swift      앱 (SwiftUI 화면 + 설치·제거·상태 확인)
AdServer/main.swift          빈 광고 서버 (Network.framework, root로 시작 → nobody)
scripts/install-adserver.sh  관리자 권한 설치: 인증서·키, 서버, LaunchDaemon, hosts
scripts/uninstall-adserver.sh 관리자 권한 제거: 위 전부 + 루프백 주소
scripts/make-icon.swift/.sh  아이콘 레이어 그리기와 Icon Composer 형식 컴파일 (Xcode 26+)
Icon/AppIcon.icon            Icon Composer 원본 (노란 바탕 + 말풍선 레이어, 유리·그림자 효과 끔)
Icon/compiled/               컴파일된 Assets.car, AppIcon.icns (빌드는 이것만 쓴다)
build.sh, scripts/make-dmg.sh
```

### 앱 흐름

1. 처음 실행하면 언어 → 설치 화면이 나옵니다. **설치**를 누르면 다음 순서로 진행합니다.
   1. `install-adserver.sh`를 관리자 권한으로 실행합니다(`do shell script … with administrator privileges`).
   2. 앱이 **사용자 권한**으로 인증서 신뢰를 등록합니다(`SecTrustSettingsSetTrustSettings`, `.user`).
   3. 로그인 항목을 등록합니다.
   4. 카카오톡을 다시 시작합니다.
2. 설치 뒤 앱을 열면 상태 화면이 나옵니다. 상태는 카카오톡과 같은 방식으로 `https://serv.ds.kakao.com/sdk/banner`를 요청해 봐서 정합니다. 응답에 서버의 `X-KleanTalk: 1` 헤더가 있으면 "작동 중"입니다.
3. 로그인 때는 `--background`로 창 없이 실행합니다. 6시간마다 상태를 확인하고, 작동하지 않으면 창을 띄웁니다.
4. 같은 앱을 또 열면, 새로 뜬 쪽이 이미 실행 중인 쪽에 "창을 보여 달라"는 알림(분산 알림)을 보내고 바로 종료합니다.

## 왜 이렇게 했나

- **광고를 막기만 하면 안 되는 이유**
  - 카카오톡은 광고 요청이 실패하면 앱 안에 들어 있는 홍보 배너("오늘의 카카오가 궁금하다면?")를 띄웁니다. 그 문구는 카카오 서버가 보내 줍니다.
  - 그래서 광고 요청을 *성공*시키되 내용만 비웁니다.
- **응답 형식**
  - mitmproxy로 실제 응답을 봤습니다. `status`, `id`, `ads[]`, `options`로 된 JSON이고, 광고 하나에는 `content`(HTML), `mimeType`, `width/height`, `feedback`, `dspId`, `bidId`, `etxId`, `cid/crid/adid`, `type`이 들어 있습니다.
  - `content`만 바꾸고 나머지 값도 **진짜와 같은 모양으로 채워야** 카카오톡이 받아들입니다. 비워 두면 한 번 다시 요청한 뒤 광고 자리를 짙은 회색(#1E1E1E)으로 비워 둡니다.
- **광고 HTML과 앱 사이의 신호**
  - 원래 광고 HTML은 앱이 `ReadyToListen`을 보내면 `{"event":{"name":"AdLoaded","data":{"result":true}}}`로 답합니다(`window.chrome.webview`).
  - 빈 광고 HTML도 같은 신호를 보냅니다.
- **빈 광고의 색**
  - 다크 모드에서 실측했습니다. 사이드바 77px `#2D2D2D`, 구분선 1px `#383838`, 목록 `#222222`입니다.
  - 그래서 창과 픽셀 단위로 같습니다. 라이트 모드는 아직 실측하지 않았습니다.
- **인증서**
  - 인증 기관이 아닌 `serv.ds.kakao.com` 전용 일반 인증서입니다(`CA:FALSE`, 825일). 자기 서명이라 `trustRoot`로 등록합니다. `trustAsRoot`는 매개변수 오류가 납니다.
  - 관리자 권한 스크립트 안에서 `security add-trusted-cert`를 쓰면 *"no user interaction was possible"*로 거부됩니다. 그래서 신뢰 등록은 앱이 사용자 권한으로 합니다.
  - 다시 설치할 때 인증서가 30일 넘게 남아 있으면 그대로 써서, 신뢰 확인 창이 다시 뜨지 않습니다.
- **기본 루프백 주소 `127.0.0.1`**
  - 재부팅 후에도 별칭 생성 없이 사용할 수 있습니다. 이전 버전의 `127.84.11.1` 별칭은 재설치 시 제거합니다.
  - IPv6(`serv.ds.kakao.com`의 `::`)는 막아 둬서 카카오톡이 IPv4로 연결합니다.
  - 같은 `127.0.0.1:443`을 쓰는 개발 도구와는 동시에 사용할 수 없습니다.
- **서버 권한:** 키를 읽고 443을 연 뒤 `nobody`로 내려갑니다.
- **다른 HTTPS 서버와 공존:** macOS 13 이상에서는 launchd가 `127.0.0.1:443`을 열고 서버에 전달합니다. Network.framework가 포트를 직접 예약하면 Tailscale처럼 다른 주소에서 443을 사용하는 서비스와도 충돌할 수 있습니다. macOS 12는 기존 직접 리스너를 사용하므로 이 충돌 회피는 지원하지 않습니다. `python3 tests/adserver_launchd_test.py`는 임시 사용자 서비스와 인증서로 포트 공존 및 TLS 응답을 검사합니다.
- **아이콘**
  - macOS 26은 최신 SDK로 빌드한 앱의 옛 형식(.icns) 아이콘에 흐릿한 유리 효과를 입히고, 작은 크기에서는 회색 틀 안에 줄여 넣습니다.
  - 그래서 Icon Composer 형식(`.icon`)을 actool로 컴파일하고, 유리·반사·그림자를 끕니다.
  - SDK를 낮추면 아이콘은 괜찮아지지만, 버튼 등이 macOS 26 스타일이 아니게 됩니다.

## 개인용 빌드와 앱 교체

- 앱 내부의 버전 확인·다운로드·설치 기능과 외부 업데이트 라이브러리를 제거했습니다.
- `./build.sh`는 현재 소스로 `build/NoAdsTalk.app`을 만듭니다. `./build.sh --install`은 이를 `~/Applications`에 복사합니다.
- 앱을 교체하려면 실행 중인 NoAdsTalk을 종료하고, 검토한 소스를 빌드한 뒤 `open ~/Applications/NoAdsTalk.app`으로 실행합니다.
- `./scripts/make-dmg.sh`로 로컬 DMG를 만들 수 있습니다. 원격 릴리스 게시 스크립트는 제공하지 않습니다.
- 앱과 설치된 서버가 다르면 SHA-256 비교로 이를 감지합니다. **다시 설치**는 앱에 포함된 서버를 설치하며, 인증서가 유효하면 재사용합니다.
- 빌드는 외부 파일을 다운로드하지 않습니다. Xcode와 저장소에 포함된 소스·아이콘을 사용합니다.
- Xcode 16.2 SDK에는 서버가 사용하는 `SecIdentityCreate` 선언이 없어 `AdServer/SecurityCompat.h`로 보완합니다. 기존 시스템 함수를 그대로 호출하며 키체인에 키를 추가하지 않습니다.

## 개발용 미리 보기

화면을 확인하거나 스크린샷을 찍을 때 씁니다.

```bash
KLEANTALK_PREVIEW=install KLEANTALK_LANG=en build/NoAdsTalk.app/Contents/MacOS/NoAdsTalk
# KLEANTALK_PREVIEW = language | install | status | uninstall
```

빈 광고 서버를 시험할 때는 다음처럼 띄웁니다. `--cacert`로 시험용 인증서를 지정해 확인합니다.

```bash
KLEANTALK_ADSERVER_HOST=127.0.0.1 KLEANTALK_ADSERVER_PORT=18443 ./kleantalk-adserver cert.der key.der
```

## 지난 방식 (참고)

처음에는 광고 자리 위에 같은 색 창을 띄워 가리는 '가림판'을 썼습니다. 창 순서, 데스크톱 전환, Mission Control 때마다 깜박임과 어긋남을 완전히 없앨 수 없어서 빈 광고 방식으로 바꿨습니다.

## 개인용 앱 이름

앱 이름·실행 파일·앱 번들·DMG 이름은 `NoAdsTalk`입니다. 기존 서버 설치 경로와 서비스 식별자, 번들 식별자(`com.myungchul.kleantalk`), 응답 헤더는 재설치 호환성을 위해 유지합니다.
