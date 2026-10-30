#!/bin/zsh
# 배포용 build/NoAdsTalk.dmg를 만든다. (앱 + 응용 프로그램 폴더 바로가기)
set -euo pipefail
cd "${0:A:h}/.."
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
STAGE=build/dmg
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R build/NoAdsTalk.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f build/NoAdsTalk.dmg
hdiutil create -volname "NoAdsTalk $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/NoAdsTalk.dmg >/dev/null
rm -rf "$STAGE"
echo "만듦: build/NoAdsTalk.dmg ($(du -h build/NoAdsTalk.dmg | cut -f1))"
