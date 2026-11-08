#!/bin/bash
# 星语机 iOS 一键编译脚本（GitHub Codespaces 专用）
# 在仓库根目录运行: bash xingyuji_ios/build_ipa.sh
# 或者先 cd xingyuji_ios && bash build_ipa.sh

set -e

echo "=== 星语机 iOS 编译 ==="

# 自动检测路径
if [ -f "XingyujiApp.swift" ]; then
  # 已经在 xingyuji_ios 目录里
  echo "检测到已在 xingyuji_ios 目录"
elif [ -d "xingyuji_ios" ]; then
  cd xingyuji_ios
  echo "进入 xingyuji_ios 目录"
else
  echo "错误：找不到源码，请确认在正确目录运行"
  exit 1
fi

echo "[1/5] 检查 XcodeGen..."
if ! command -v xcodegen &> /dev/null; then
  echo "安装 XcodeGen..."
  # 用 brew 安装，如果失败则下载二进制
  if command -v brew &> /dev/null; then
    brew install xcodegen
  else
    # 直接下载预编译二进制
    curl -L https://github.com/yonaskolb/XcodeGen/releases/download/2.42.0/xcodegen.zip -o /tmp/xcodegen.zip
    unzip -q /tmp/xcodegen.zip -d /tmp/xcodegen
    sudo cp /tmp/xcodegen/bin/xcodegen /usr/local/bin/ 2>/dev/null || cp /tmp/xcodegen/bin/xcodegen ~/.local/bin/ 2>/dev/null || {
      mkdir -p ~/bin
      cp /tmp/xcodegen/bin/xcodegen ~/bin/
      export PATH="$HOME/bin:$PATH"
    }
  fi
fi

xcodegen --version || { echo "XcodeGen 安装失败"; exit 1; }

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
  build 2>&1 | tail -20

echo "[4/5] 打包 ipa..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Xingyuji.app" -path "*Release-iphoneos*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "错误：找不到编译产物，编译可能失败了"
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
echo "1. 在 Codespaces 左侧文件树找到 xingyuji_ios/星语机.ipa"
echo "2. 右键 → Download"
echo "3. 发给朋友，用 SideStore/Sideloadly 安装"
