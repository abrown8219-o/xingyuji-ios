#!/bin/bash
# 星语机 iOS 一键编译脚本（GitHub Codespaces 专用）
# 在仓库根目录 /workspaces/xingyuji-ios 运行: bash build_ipa.sh

set -e

echo "=== 星语机 iOS 编译 ==="
echo "当前目录: $(pwd)"

# 检查是否在正确位置
if [ ! -f "XingyujiApp.swift" ]; then
  echo "错误：当前目录没有 XingyujiApp.swift"
  echo "请确认在仓库根目录运行"
  exit 1
fi

echo "[1/5] 安装 XcodeGen..."
XCODEGEN_VERSION="2.42.0"
mkdir -p ~/.local/bin

# 下载并解压
curl -sL "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip" -o /tmp/xcodegen.zip
unzip -q -o /tmp/xcodegen.zip -d /tmp/xcodegen
cp /tmp/xcodegen/bin/xcodegen ~/.local/bin/

# 立即生效并验证
export PATH="$HOME/.local/bin:$PATH"
echo "PATH: $PATH"
ls -la ~/.local/bin/xcodegen

if ! ~/.local/bin/xcodegen --version; then
  echo "XcodeGen 安装失败"
  exit 1
fi

echo "[2/5] 生成 Xcode 工程..."
~/.local/bin/xcodegen

echo "[3/5] 编译 Release 版本..."
xcodebuild \
  -project Xingyuji.xcodeproj \
  -scheme Xingyuji \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -30

echo "[4/5] 打包 ipa..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Xingyuji.app" -path "*Release-iphoneos*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "错误：找不到编译产物"
  echo "可能编译失败了，请把上面的红色错误发给我"
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
