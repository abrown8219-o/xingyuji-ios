#!/bin/bash
# 星语机 iOS 一键编译脚本（GitHub Codespaces / macOS 专用）
# 使用方法：打开 Codespaces → 新建终端 → 粘贴运行: bash build_ipa.sh

set -e

echo "=== 星语机 iOS 编译 ==="

cd "$(dirname "$0")"

echo "[1/5] 安装 XcodeGen..."
brew install xcodegen 2>/dev/null || true

echo "[2/5] 生成 Xcode 工程..."
xcodegen

echo "[3/5] 编译 Release 版本..."
xcodebuild \
  -project Xingyuji.xcodeproj \
  -scheme Xingyuji \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "[4/5] 打包 ipa..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Xingyuji.app" -path "*Release-iphoneos*" | head -1)
if [ -z "$APP_PATH" ]; then
  echo "错误：找不到编译产物"
  exit 1
fi

mkdir -p Payload
cp -r "$APP_PATH" Payload/
zip -qr 星语机.ipa Payload

echo "[5/5] 完成！"
echo ""
echo "=== 编译成功 ==="
echo "ipa 位置: $(pwd)/星语机.ipa"
echo "文件大小: $(du -h 星语机.ipa | cut -f1)"
echo ""
echo "下载方法："
echo "1. 在 Codespaces 左侧文件树找到 星语机.ipa"
echo "2. 右键 → Download"
echo "3. 发给朋友，用 SideStore/Sideloadly 安装"
