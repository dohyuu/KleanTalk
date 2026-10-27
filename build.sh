#!/bin/zsh
# KleanTalk.app을 빌드한다. 빈 광고 서버(kleantalk-adserver)와 설치·제거 스크립트도 앱 안(Contents/Resources)에 넣는다.
# 사용: ./build.sh            → build/KleanTalk.app
#       ./build.sh --install  → 빌드한 뒤 ~/Applications에 복사
# 배포용 dmg: ./scripts/make-dmg.sh
set -euo pipefail
cd "${0:A:h}"

APP="build/KleanTalk.app"

# 자동 업데이트(Sparkle). 없으면 공식 릴리스를 받아 SHA-256을 확인한 뒤 vendor/에 푼다.
SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE="vendor/Sparkle-$SPARKLE_VERSION"
if [[ ! -d $SPARKLE/Sparkle.framework ]]; then
  mkdir -p vendor
  curl -fsSL -o "$SPARKLE.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  $SPARKLE.tar.xz" | shasum -a 256 -c -
  mkdir -p "$SPARKLE" && tar -xJf "$SPARKLE.tar.xz" -C "$SPARKLE"
fi
RES="$APP/Contents/Resources"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$RES"
cp Info.plist "$APP/Contents/Info.plist"
# 개발용: 업데이트를 시험할 때만 빌드 번호를 바꾼다 (KLEANTALK_BUILD_NUMBER)
[[ -n ${KLEANTALK_BUILD_NUMBER:-} ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $KLEANTALK_BUILD_NUMBER" "$APP/Contents/Info.plist"
# 지원 언어 폴더 (macOS 기본 창·메뉴가 앱 언어와 맞게 뜨도록)
for lang in ko en; do mkdir -p "$RES/$lang.lproj"; done

# Apple Silicon(arm64)과 Intel(x86_64)용으로 각각 컴파일해 하나의 유니버설 실행 파일로 합친다
universal() {   # universal <출력> <swiftc 인자...>
  local out=$1; shift
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos14.0 -o "build/$arch-${out:t}" "$@"
  done
  lipo -create "build/arm64-${out:t}" "build/x86_64-${out:t}" -output "$out"
  rm -f "build/arm64-${out:t}" "build/x86_64-${out:t}"
}

universal "$APP/Contents/MacOS/KleanTalk" -parse-as-library -F "$SPARKLE" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/*.swift
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# 빈 광고 서버와 설치·제거 스크립트 (설치하면 root 전용 폴더로 복사된다)
universal "$RES/kleantalk-adserver" AdServer/main.swift
install -m 755 scripts/install-adserver.sh scripts/uninstall-adserver.sh "$RES/"

# 아이콘: 미리 컴파일해 둔 Icon Composer 형식 (바꾸려면 scripts/make-icon.sh, Xcode 필요)
cp Icon/compiled/Assets.car Icon/compiled/AppIcon.icns "$RES/"

# 확장 속성(Finder 정보 등)이 남아 있으면 서명이 거부되므로 지운다
xattr -cr "$APP"
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$RES/kleantalk-adserver"
codesign --force --sign - "$APP"
echo "빌드됨: $APP"

if [[ ${1:-} == --install ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/KleanTalk.app
  cp -R "$APP" ~/Applications/
  echo "설치됨: ~/Applications/KleanTalk.app"
fi
