#!/bin/zsh
# NoAdsTalk.app을 빌드한다. 빈 광고 서버(kleantalk-adserver)와 설치·제거 스크립트도 앱 안(Contents/Resources)에 넣는다.
# 사용: ./build.sh            → build/NoAdsTalk.app
#       ./build.sh --install  → 빌드한 뒤 ~/Applications에 복사
# 배포용 dmg: ./scripts/make-dmg.sh
set -euo pipefail
cd "${0:A:h}"

APP="build/NoAdsTalk.app"

# macOS 12용 Intel 빌드에 필요한 Swift 호환 라이브러리(x86_64)는 Command Line Tools에 없고 Xcode에만 있다
if [[ -z ${DEVELOPER_DIR:-} ]]; then
  [[ -d /Applications/Xcode.app ]] || { echo "Xcode가 필요합니다 (/Applications/Xcode.app)" >&2; exit 1; }
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

RES="$APP/Contents/Resources"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$RES"
cp Info.plist "$APP/Contents/Info.plist"
# 지원 언어 폴더 (macOS 기본 창·메뉴가 앱 언어와 맞게 뜨도록)
for lang in ko en; do mkdir -p "$RES/$lang.lproj"; done

# Apple Silicon(arm64)과 Intel(x86_64)용으로 각각 컴파일해 하나의 유니버설 실행 파일로 합친다
universal() {   # universal <출력> <swiftc 인자...>
  local out=$1; shift
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos12.0 -o "build/$arch-${out:t}" "$@"
  done
  lipo -create "build/arm64-${out:t}" "build/x86_64-${out:t}" -output "$out"
  rm -f "build/arm64-${out:t}" "build/x86_64-${out:t}"
}

universal "$APP/Contents/MacOS/NoAdsTalk" -parse-as-library Sources/*.swift

# 빈 광고 서버와 설치·제거 스크립트 (설치하면 root 전용 폴더로 복사된다)
universal "$RES/kleantalk-adserver" -import-objc-header AdServer/SecurityCompat.h AdServer/main.swift
install -m 755 scripts/install-adserver.sh scripts/uninstall-adserver.sh "$RES/"

# 아이콘: 미리 컴파일해 둔 Icon Composer 형식 (바꾸려면 scripts/make-icon.sh, Xcode 필요)
cp Icon/compiled/Assets.car Icon/compiled/AppIcon.icns "$RES/"

# 확장 속성(Finder 정보 등)이 남아 있으면 서명이 거부되므로 지운다
xattr -cr "$APP"
codesign --force --sign - "$RES/kleantalk-adserver"
codesign --force --sign - "$APP"
echo "빌드됨: $APP"

if [[ ${1:-} == --install ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/NoAdsTalk.app
  cp -R "$APP" ~/Applications/
  echo "설치됨: ~/Applications/NoAdsTalk.app"
fi
