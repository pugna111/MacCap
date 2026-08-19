#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
DMG_PATH="${1:-$ROOT_DIR/dist/MacCap-$VERSION.dmg}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：公证流程需要 macOS 与 Xcode。" >&2
  exit 1
fi
: "${MACCAP_NOTARY_PROFILE:?请先设置 MACCAP_NOTARY_PROFILE（notarytool 钥匙串配置名称）}"
[[ -f "$DMG_PATH" ]] || { echo "错误：找不到 $DMG_PATH" >&2; exit 1; }

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$MACCAP_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
echo "公证完成：$DMG_PATH"
