#!/usr/bin/env bash
# 配布用の build/Kinko-<版>.dmg を作る。開くと Kinko とアプリケーションフォルダが並び、ドラッグで入れる形。
#
# 何も指定しなければ、build-app.sh の ad-hoc 署名のまま作る（受け取った人は最初の 1 回だけ「このまま開く」が要る）。
# Apple Developer Program に入っていれば、次を指定すると Developer ID で署名し、Apple の公証（notarization）まで通す:
#   SIGN_IDENTITY="Developer ID Application: 名前 (チームID)"  署名に使う証明書
#   NOTARY_PROFILE="kinko"  `xcrun notarytool store-credentials kinko` で保存した認証情報の名前
# DMG_LAYOUT=0 にすると、Finder でのアイコンの並べ方を省く（Finder を操作する許可を求められたくないとき）
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Kinko.app"

"$root/scripts/build-app.sh"

version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")"
name="Kinko $version"
dmg="$root/build/Kinko-$version.dmg"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # 公証には Hardened Runtime と、Apple の時刻証明（--timestamp）つきの署名が要る
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
fi
codesign --verify --strict "$app"

work="$(mktemp -d)"
trap 'hdiutil detach "$work/mount" -quiet 2>/dev/null || true; rm -rf "$work"' EXIT
staging="$work/staging"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  # 公証していないアプリは、ダウンロードしたあとの最初の 1 回だけ macOS に止められるので、開き方を添える
  cat > "$staging/はじめにお読みください.txt" <<'EOF'
Kinko のインストール

1. Kinko を、右のアプリケーションフォルダへドラッグします。
2. アプリケーションフォルダの Kinko をダブルクリックします。
   初めてのときは「開発元を確認できない」などと表示されて開きません（Apple の公証を受けていないため）。
3. 「システム設定」>「プライバシーとセキュリティ」を開き、下のほうの「このまま開く」を押します。
4. 次からは、ふつうにダブルクリックで開けます。

ターミナルを使える人は、2〜3 の代わりに次のコマンドでも開けるようになります。
  xattr -dr com.apple.quarantine /Applications/Kinko.app

注意：金庫（.kinko）のパスワードを忘れると、中身は誰にも取り出せません。
EOF
fi

# いったん書き込める形で作り、Finder でアイコンを並べてから、圧縮した読み取り専用の形に変える
hdiutil create -quiet -volname "$name" -srcfolder "$staging" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
mkdir -p "$work/mount"
hdiutil attach -quiet -noautoopen -mountpoint "$work/mount" "$work/rw.dmg"
if [[ "${DMG_LAYOUT:-1}" != "0" ]]; then
  # Finder を操作するので、初回は「Finder を制御する許可」を求められる。断られたり 30 秒で終わらなければ、並べ方を省く
  osascript - "$work/mount" <<'EOF' &
on run argv
  tell application "Finder"
    set theDisk to (POSIX file (item 1 of argv) as alias)
    open theDisk
    set theWindow to container window of theDisk
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {200, 120, 760, 480}
    set theOptions to icon view options of theWindow
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 112
    set text size of theOptions to 13
    set position of item "Kinko.app" of theWindow to {140, 150}
    set position of item "Applications" of theWindow to {420, 150}
    try
      set position of item "はじめにお読みください.txt" of theWindow to {280, 290}
    end try
    update theDisk without registering applications
    delay 1
    close theWindow
  end tell
end run
EOF
  layout=$!
  for _ in $(seq 30); do kill -0 "$layout" 2>/dev/null || break; sleep 1; done
  if kill -0 "$layout" 2>/dev/null; then
    kill "$layout" 2>/dev/null || true
    echo "note: Finder でのアイコンの並べ方を省きました（許可がないか、時間がかかりすぎた）" >&2
  elif ! wait "$layout"; then
    echo "note: Finder でのアイコンの並べ方を省きました（許可がないか、時間がかかりすぎた）" >&2
  fi
fi
# .fseventsd などの作業用のフォルダは配る必要がない
rm -rf "$work/mount/.fseventsd" "$work/mount/.Trashes" 2>/dev/null || true
sync
hdiutil detach -quiet "$work/mount"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    # Apple に送って確かめてもらい、結果（ticket）を DMG に貼り付ける。これでネットにつながっていなくても開ける
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
  fi
fi

shasum -a 256 "$dmg"
echo "built $dmg"
