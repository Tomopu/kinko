#!/usr/bin/env bash
# build/Kinko.app を組み立てて、Hardened Runtime つきで ad-hoc 署名する。
# 自分の Mac で使うだけなら、Apple Developer Program の証明書も期限もない。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --package-path "$root"
bin="$(swift build -c release --package-path "$root" --show-bin-path)/Kinko"
app="$root/build/Kinko.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# SwiftPM はバイナリに SDK バージョンとして最小対応 OS（14.0）を書き込む。
# そのままだと macOS が「古い SDK のアプリ」とみなし、旧来の見た目の互換モードで表示する（ツールバーに段差が出る）ので、実際の SDK バージョンに直す
sdk="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos 14.0 "$sdk" -replace -output "$app/Contents/MacOS/Kinko" "$bin" 2>/dev/null
cp "$root/Config/Info.plist" "$app/Contents/Info.plist"
# Icon Composer のアイコンから Assets.car（macOS 26 以降）と AppIcon.icns（それより前）を作る
xcrun actool "$root/Resources/AppIcon.icon" --compile "$app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist /dev/null >/dev/null
codesign --force --options runtime --sign - "$app"
codesign --verify --strict "$app"
echo "built $app"
