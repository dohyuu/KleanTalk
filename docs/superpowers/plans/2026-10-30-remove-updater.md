# 업데이트 기능 제거 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 업데이트 공급 경로를 제거한 개인용 앱을 빌드·설치하고 실제 광고 차단을 확인한다.

**Architecture:** 기존 Swift 앱에서 업데이트 관련 코드만 삭제한다. 로컬 광고 서버와 설치 흐름은 유지하고 Sparkle 없이 빌드한다.

**Tech Stack:** Swift, SwiftUI, AppKit, CryptoKit, Network.framework, zsh, Xcode.

**Spec:** `docs/superpowers/specs/2026-10-30-remove-updater-design.md`

## Global Constraints

- 기존 macOS 12 이상, arm64·x86_64 universal 빌드와 ad-hoc 서명을 유지한다.
- 광고 차단·설치·복구·제거·로그인 시 상태 점검은 유지한다.
- 관리자 암호와 인증서 신뢰 확인은 사용자만 처리한다.
- 자동 업데이트 릴리스 게시와 별도 업데이트 시스템 도입은 하지 않는다. 소스 커밋·push는 후속 사용자 요청으로 승인됐다.

## Review Focus

- 기존 자동 업데이트 설정이나 개발용 환경 변수로 업데이트가 다시 켜지지 않아야 한다.
- 정상 실행과 백그라운드 실행에서 업데이트 확인 코드가 남지 않아야 한다.
- 한글·영문 화면에서 삭제된 업데이트 상태·메뉴 참조가 남지 않아야 한다.
- 구버전 앱이 실행 중이면 새 앱 대신 기존 앱이 활성화되는 상황을 전환 전에 확인한다.
- 앱 재빌드 후 서버 불일치 안내와 재설치 기능이 유지되어야 한다.

### Task 1: 업데이트 경로 삭제와 빌드

**Files:** `Sources/KleanTalk.swift`, `Info.plist`, `build.sh`, `README.md`, `docs/DEVELOPMENT.md`; 삭제 `scripts/release.sh`.

**Interfaces:** 기존 앱의 설치·상태 확인 API와 `build/NoAdsTalk.app` 산출물을 그대로 유지한다.

- [x] Sparkle 없이 `swiftc -typecheck -parse-as-library Sources/KleanTalk.swift`를 실행하여 현재 `no such module 'Sparkle'` 실패를 확인한다. 캐시는 `/private/tmp/kleantalk-module-cache`를 사용한다.
- [x] 설계에 명시한 업데이트 코드·설정·빌드 의존성과 배포 스크립트를 제거하고 사용 문서를 맞춘다.
- [x] 같은 typecheck를 통과시키고 `plutil -lint Info.plist`, `zsh -n build.sh`, `git diff --check`를 실행한다. 기대 결과: 모두 종료 코드 0.
- [x] `./build.sh`를 실행한다. 기대 결과: `build/NoAdsTalk.app` 생성, 앱과 서버 모두 arm64·x86_64 지원.
- [x] `otool -L`, 번들 파일 목록, plist와 코드 검색으로 Sparkle·업데이트 공급 경로 부재를 확인한다. `codesign --verify --deep --strict`가 성공해야 한다.
- [x] 코드 리뷰를 받아 중요 결함 여부를 확인했다. 원본 체크아웃에 수정 사항을 반영했고, 후속 사용자 요청에 따라 main에서 커밋·push한다.

### Task 2: 로컬 설치와 광고 차단 검증

**Files:** 사용자용 `~/Applications/NoAdsTalk.app`, 앱이 관리하는 기존 서비스·hosts·인증서·로그인 항목.

**Interfaces:** Task 1의 검증된 앱과 기존 설치 UI를 사용한다.

- [x] 현재 설치·실행 상태를 확인하고 작업 결과를 원본 체크아웃에 반영한다. 기존 앱이 있다면 복구 가능한 백업을 남긴다.
- [x] 새 앱을 사용자용 경로에 복사했고 사용자가 실행했다. 한국어 화면과 실사용을 확인했다. 영문 실행 화면 검증은 수행하지 않았다.
- [x] 앱의 설치 흐름을 실행하고 macOS 인증 화면이 뜨면 사용자가 직접 처리하도록 안내한다.
- [x] LaunchDaemon, hosts의 루프백 매핑, 인증서와 HTTPS 빈 광고 응답을 확인한다.
- [x] 카카오톡 재실행 후 광고 영역을 확인한다. 직접 화면 확인을 못 하면 사용자 확인이 필요한 항목으로 남긴다.
- [x] 최종 검증 결과·설치 위치·남은 제약을 기록한다.

## 실행 기록

- 설계 승인을 구현 승인으로 적용하여 추가 계획 승인 없이 직접 실행한다.
- 기존 테스트 체계가 없고 기능을 삭제하는 작업이므로 소스 문자열을 고정하는 회귀 테스트는 추가하지 않는다. 실제 컴파일·번들·UI·설치 동작으로 검증한다.
- 분리 작업 공간: `/private/tmp/kleantalk-remove-updater`, 브랜치 `codex/remove-updater`, 기준 `b2a273a1abde436fb04fbe500456c81d781c69e9`.
- Ruling: 현재 Xcode 16.2에서 기존 서버의 `SecIdentityCreate` 선언 부재로 전체 빌드가 실패했다. SDK의 Security.tbd에는 심볼이 있고 Apple 문서상 macOS 10.12부터 제공된다. `AdServer/SecurityCompat.h`에 소유권과 nullability를 포함한 선언을 추가하여 기존 서버 동작을 보존한다. 잘못된 ABI 선언은 TLS 서버 실행에 영향을 줄 수 있으므로 컴파일뿐 아니라 실제 TLS 응답도 검증한다.

- 사용자 추가 지시: 개인용 이름을 `NoAdsTalk`으로 변경하고 다시 설치한다. 앱 파일·실행 파일·UI·DMG 이름을 변경하고 서비스 및 인증서 경로는 유지한다. 사용자가 직접 실행·설치하기로 했으므로 시스템 설치/UI 검증은 사용자 인계로 남긴다.

### 검증 결과

- Sparkle 없는 앱 typecheck 성공. NoAdsTalk 앱과 서버 universal 빌드 성공.
- plist·셸 문법·diff 공백·코드 서명 검증 성공. 번들에 업데이트 설정과 Sparkle 라이브러리 없음.
- 임시 인증서·127.0.0.1:18443에서 인증서를 검증한 TLS 연결, HTTP 200, X-KleanTalk 헤더, 빈 광고 JSON과 AdLoaded 신호를 확인했다.
- 별도 코드 리뷰에서 중요 결함 없음. 이름 변경 과정의 문서 헤더 오기는 수정했다.
- 이 시점에는 시스템 설치와 화면 확인을 사용자에게 인계했다. 이후 완료 결과는 아래 최종 실사용 확인에 기록했다.

### 실사용 포트 충돌 수정 (2026-10-30)

- 설치 후 launchd 서비스가 error 48로 반복 종료했다. Tailscale가 별도 주소에서 443을 점유하고 있었다. hosts와 인증서는 정상이었다.
- 실제 Network.framework 리스너가 다른 주소의 동일 포트와 충돌함을 임시 고포트로 재현했다.
- macOS 13+에서 launchd가 소켓을 열고 서버로 전달하도록 변경했다. macOS 12와 직접 실행은 기존 경로를 유지한다.
- 재부팅 후 별칭 누락을 피하려고 기본 루프백 `127.0.0.1`로 변경했다. 이전 별칭만 정리하며 기존 Tailscale 설정은 변경하지 않는다. 같은 `127.0.0.1:443`을 사용하는 다른 서비스와는 공존할 수 없다.
- `tests/adserver_launchd_test.py`: 기존 실제 바이너리에서 TLS timeout 실패를 확인했고 수정 후 통과했다. 임시 launchd 서비스, 다른 IPv6 주소의 동일 포트, 인증서 검증, HTTP 200 및 빈 광고 응답을 검사한다.
- 별도 리뷰가 지적한 재부팅 회귀를 위 기본 루프백 전환으로 해결했다. 실제 재부팅 검증은 수행하지 않았다.
- 시스템 서비스 갱신에는 사용자 관리자 인증을 통한 다시 설치가 필요하다.

### 최종 실사용 확인

- 사용자가 수정본의 다시 설치를 완료하고 카카오톡 광고가 가려졌다고 확인했다.
- 시스템 LaunchDaemon이 running이며, 서버 UID/GID가 -2(nobody)임을 확인했다.
- 앱과 동일한 URLSession 기본 인증서 검증으로 HTTP 200, X-KleanTalk 헤더와 빈 광고 JSON을 확인했다. security verify-cert도 성공했다. curl 기본 CA 처리에서는 issuer 오류가 있었으나 URLSession과 macOS 신뢰 검증은 정상이다.
- 설치된 서버와 앱 번들의 서버 SHA-256이 일치한다.
- NoAdsTalk은 127.0.0.1:443, 기존 Tailscale은 별도 주소의 443에서 동시에 LISTEN 중이다.
- 로그인 항목이 임시 빌드 폴더를 가리켜 설치 경로 ~/Applications/NoAdsTalk.app으로 수정했다.
- 실제 재부팅 시험은 하지 않았다.
