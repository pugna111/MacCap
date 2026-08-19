#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MacCap.app"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
DMG_PATH="$DIST_DIR/MacCap-$VERSION.dmg"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：DMG 必须在 macOS 上使用 hdiutil 创建。" >&2
  exit 1
fi

if [[ "${1:-}" != "--skip-build" ]]; then
  bash "$ROOT_DIR/scripts/build-app.sh"
fi
[[ -d "$APP_DIR" ]] || { echo "错误：找不到 $APP_DIR" >&2; exit 1; }

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "MacCap 安装" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

if [[ -n "${MACCAP_SIGN_IDENTITY:-}" && "$MACCAP_SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$MACCAP_SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
rm -rf "$STAGING_DIR"
echo "完成：$DMG_PATH"
