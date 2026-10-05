#!/bin/bash
# 第 7 步 C 段：构建「书源调试」iOS App 并打包为 IPA（无签名，供真机侧载/分发给开发调试）。
# 步骤：xcodegen 生成工程 → xcodebuild archive（Release）→ 校验 MinimumOSVersion → Payload 打包 ipa。
# 用法（CI）：GIT_COMMIT=<sha> CI_RUN_ID=<run> bash scripts/build_ipa.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

GIT_COMMIT="${GIT_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
CI_RUN_ID="${CI_RUN_ID:-local}"

echo "== 1/4 生成 Xcode 工程 =="
xcodegen generate
# 校验工程格式能被当前 Xcode 读取（防止 XcodeGen 默认 xcode16_0 格式在 Xcode 15 runner 上报
# 「future Xcode project file format」这类不指向 project.yml 的晦涩错误）。
bash scripts/verify_xcodeproj_format.sh BookonDebug.xcodeproj

echo "== 2/4 归档（Release，无签名）=="
xcodebuild archive \
  -project BookonDebug.xcodeproj \
  -scheme BookonDebug \
  -configuration Release \
  -archivePath build/BookonDebug.xcarchive \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  GIT_COMMIT="$GIT_COMMIT" \
  CI_RUN_ID="$CI_RUN_ID"

APP_PATH="build/BookonDebug.xcarchive/Products/Applications/BookonDebug.app"
if [ ! -d "$APP_PATH" ]; then
  echo "错误：找不到归档产物 $APP_PATH" >&2
  exit 1
fi

echo "== 3/4 校验 Info.plist（MinimumOSVersion 必须为 17.0）=="
plutil -p "$APP_PATH/Info.plist" | grep -E "MinimumOSVersion|BuildCommit|BuildCIRun" || true
MINOS=$(plutil -extract MinimumOSVersion raw "$APP_PATH/Info.plist" 2>/dev/null || echo "")
if [ "$MINOS" != "17.0" ]; then
  echo "错误：MinimumOSVersion 不是 17.0（实际：${MINOS}）" >&2
  exit 1
fi
echo "MinimumOSVersion = ${MINOS} ✓"

echo "== 4/4 打包 IPA =="
rm -rf build/Payload
mkdir -p build/Payload
cp -R "$APP_PATH" build/Payload/
(cd build && zip -qr BookonDebug.ipa Payload)

echo "IPA 已生成: build/BookonDebug.ipa"
ls -la build/BookonDebug.ipa
