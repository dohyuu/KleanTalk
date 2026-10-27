#!/bin/zsh
# 배포용 build/KleanTalk.dmg를 만든다. (앱 + 응용 프로그램 폴더 바로가기)
set -euo pipefail
cd "${0:A:h}/.."
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
STAGE=build/dmg
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R build/KleanTalk.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f build/KleanTalk.dmg
hdiutil create -volname "KleanTalk $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/KleanTalk.dmg >/dev/null
rm -rf "$STAGE"
echo "만듦: build/KleanTalk.dmg ($(du -h build/KleanTalk.dmg | cut -f1))"
