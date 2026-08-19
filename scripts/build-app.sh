#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MacCap.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：MacCap 只能在安装了 Xcode 的 macOS 上构建。" >&2
  exit 1
fi

for tool in xcrun lipo codesign plutil; do
  command -v "$tool" >/dev/null || { echo "缺少构建工具：$tool" >&2; exit 1; }
done

echo "[1/5] 运行核心算法测试"
xcrun swift test --package-path "$ROOT_DIR"

build_arch() {
  local arch="$1"
  local scratch="$BUILD_DIR/$arch"
  xcrun swift build \
    --package-path "$ROOT_DIR" \
    --configuration release \
    --scratch-path "$scratch" \
    --arch "$arch"
  xcrun swift build \
    --package-path "$ROOT_DIR" \
    --configuration release \
    --scratch-path "$scratch" \
    --arch "$arch" \
    --show-bin-path
}

echo "[2/5] 构建 Apple Silicon"
ARM_BIN_DIR="$(build_arch arm64 | tail -n 1)"
echo "[3/5] 构建 Intel"
INTEL_BIN_DIR="$(build_arch x86_64 | tail -n 1)"

if [[ ! -x "$ARM_BIN_DIR/MacCap" || ! -x "$INTEL_BIN_DIR/MacCap" ]]; then
  echo "错误：没有找到 SwiftPM 构建产物。" >&2
  exit 1
fi

echo "[4/5] 组装通用 App"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create "$ARM_BIN_DIR/MacCap" "$INTEL_BIN_DIR/MacCap" -output "$APP_DIR/Contents/MacOS/MacCap"
chmod 755 "$APP_DIR/Contents/MacOS/MacCap"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
xcrun swift "$ROOT_DIR/scripts/generate-icon.swift" "$APP_DIR/Contents/Resources/AppIcon.icns"

plutil -lint "$APP_DIR/Contents/Info.plist"
lipo -info "$APP_DIR/Contents/MacOS/MacCap"

echo "[5/5] 签名并校验"
SIGN_IDENTITY="${MACCAP_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_DIR"
  echo "已使用 ad-hoc 签名（仅适合本机测试）。"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "完成：$APP_DIR"
