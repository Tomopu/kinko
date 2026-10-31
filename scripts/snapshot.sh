#!/usr/bin/env bash
# 開発用：主な画面を PNG に描き出し、画面の操作の確認結果（snapshot: …）を出す。出力先は引数（既定は build/snapshots）。
# デバッグビルドは SDK のバージョンが古く書かれていて古い見た目で描かれるので、build-app.sh と同じく実際の SDK に直してから動かす。
# ウィンドウは画面の外に置くので、作業中の画面の前には出てこない
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/build/snapshots}"
swift build --package-path "$root"
bin="$(swift build --package-path "$root" --show-bin-path)/Kinko"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sdk="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos 14.0 "$sdk" -replace -output "$work/Kinko" "$bin" 2>/dev/null
codesign --force --sign - "$work/Kinko" 2>/dev/null
"$work/Kinko" --snapshot "$out"
echo "wrote $out"
