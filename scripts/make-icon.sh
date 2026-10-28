#!/bin/zsh
# 앱 아이콘을 다시 만든다 (Xcode 26 이상 필요). 결과물은 Icon/compiled/에 저장돼 git에 함께 올라가므로,
# 아이콘을 바꿀 때만 실행하면 된다. 평소 빌드(./build.sh)는 Xcode 없이 Icon/compiled/를 그대로 쓴다.
#  1. scripts/make-icon.swift 로 말풍선+KLEAN 레이어(1024px, 투명 바탕)를 그린다.
#  2. Icon Composer 형식(Icon/AppIcon.icon: 노란 바탕 + 레이어, 유리·그림자 효과 끔)을 actool로 컴파일한다.
#     macOS 26은 최신 SDK로 빌드한 앱의 옛 형식(.icns) 아이콘에 흐릿한 유리 효과를 덧씌우므로 이 형식을 쓴다.
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
TMP=$(mktemp -d); trap 'rm -rf "${TMP:?}"' EXIT
swift scripts/make-icon.swift Icon/AppIcon.icon/Assets/bubble.png
xcrun actool --compile "$TMP" --platform macosx --minimum-deployment-target 12.0 --app-icon AppIcon \
  --output-partial-info-plist "$TMP/partial.plist" Icon/AppIcon.icon >/dev/null
cp "$TMP/Assets.car" "$TMP/AppIcon.icns" Icon/compiled/
echo "아이콘을 만들었습니다: Icon/compiled/"
