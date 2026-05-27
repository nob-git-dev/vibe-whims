#!/usr/bin/env bash
#
# make_app.sh — swift build -c release の実行ファイルを .app バンドルに組み立て、
# ad-hoc 署名して実機検証可能にする。
#
# 目的: bare executable では TCC（音声キャプチャ）ダイアログが不安定なため、
#       .app バンドル + 署名でバンドル識別 + Info.plist を LaunchServices/TCC に正しく認識させる。
#
# 固定要件: TCC は音声キャプチャ権限のみ（NSAudioCaptureUsageDescription）。
#           画面収録・マイク権限は要求しない（Info.plist にキーを追加しない）。
#
# 使い方:
#   scripts/make_app.sh            # release ビルド → .app 生成 → ad-hoc 署名 → 検証
#   OPEN=1 scripts/make_app.sh     # 生成後に open で起動
#
# 出力: build/SpeechTap.app
#
# 不可逆操作（rm -rf 等）は build/SpeechTap.app（このスクリプトの生成物）に限定する。
# ソース・ユーザーデータには触れない。

set -euo pipefail

# --- パス定義（リポジトリルート基準） --------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="SpeechTap"
EXECUTABLE="SpeechTapApp"          # Package.swift の executable target 名
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

INFO_PLIST_SRC="${ROOT_DIR}/Sources/SpeechTapApp/Resources/Info.plist"
CONFIG_DEFAULT_SRC="${ROOT_DIR}/Sources/SpeechTapApp/Resources/config.default.conf"
ENTITLEMENTS="${BUILD_DIR}/${APP_NAME}.entitlements"

echo "==> 1/5 release ビルド"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
EXEC_SRC="${BIN_PATH}/${EXECUTABLE}"
if [[ ! -x "${EXEC_SRC}" ]]; then
  echo "ERROR: 実行ファイルが見つからない: ${EXEC_SRC}" >&2
  exit 1
fi

echo "==> 2/5 .app バンドル構造を構築: ${APP_BUNDLE}"
# 生成物（build/SpeechTap.app）のみクリーンアップ。ソースには触れない。
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 実行ファイル（CFBundleExecutable と一致させる）。
cp "${EXEC_SRC}" "${MACOS_DIR}/${EXECUTABLE}"
chmod +x "${MACOS_DIR}/${EXECUTABLE}"

# Info.plist を Contents/ に配置（バンドル識別・TCC 説明文・LSUIElement 等）。
# 注: バイナリには -sectcreate で同内容を埋め込み済みだが、.app では Contents/Info.plist が正本。
cp "${INFO_PLIST_SRC}" "${CONTENTS}/Info.plist"

# CFBundleExecutable がバイナリ名と一致することを保証（既存値があれば上書き）。
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${EXECUTABLE}" "${CONTENTS}/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${EXECUTABLE}" "${CONTENTS}/Info.plist"

# 設定の既定値（フォールバック）を Resources に配置。
# AppDelegate は Bundle.main.path(forResource:"config.default", ofType:"conf") で参照する。
# .app では Contents/Resources/ が Bundle.main の探索先になる。
cp "${CONFIG_DEFAULT_SRC}" "${RESOURCES_DIR}/config.default.conf"

# PkgInfo（任意だが慣習）。CFBundlePackageType=APPL に対応。
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> 3/5 entitlements 生成（音声キャプチャ用・最小）"
# Process Tap / 音声キャプチャに必要な最小 entitlements。
# audio-input は音声入力（タップ）に関わるサンドボックス外でも有用な宣言。
# Hardened Runtime は付けない（ad-hoc 署名 + ローカル実機検証のため不要。
#   将来 Developer ID 配布する場合のみ runtime + notarization を検討）。
cat > "${ENTITLEMENTS}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- 音声入力（Core Audio Process Tap によるキャプチャ）。 -->
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> 4/5 ad-hoc 署名（codesign -s -）"
# --force: 再署名を許可。--options なし = Hardened Runtime 無効（ローカル検証用）。
# entitlements を埋め込んで署名する。
codesign --force --sign - \
  --entitlements "${ENTITLEMENTS}" \
  --identifier "com.example.speech-tap" \
  "${APP_BUNDLE}"

echo "==> 5/5 検証"
echo "--- codesign --verify ---"
codesign --verify --verbose=2 "${APP_BUNDLE}"
echo "--- codesign -d (entitlements) ---"
codesign -d --entitlements - --xml "${APP_BUNDLE}" 2>/dev/null | plutil -p - 2>/dev/null || true
echo "--- Info.plist 主要キー ---"
for k in CFBundleIdentifier CFBundleExecutable LSUIElement LSMinimumSystemVersion NSAudioCaptureUsageDescription; do
  v="$(/usr/libexec/PlistBuddy -c "Print :${k}" "${CONTENTS}/Info.plist" 2>/dev/null || echo '(なし)')"
  echo "  ${k} = ${v}"
done
# 画面収録・マイク権限キーが「無い」ことを明示確認（固定要件）。
for forbidden in NSScreenCaptureUsageDescription NSMicrophoneUsageDescription; do
  if /usr/libexec/PlistBuddy -c "Print :${forbidden}" "${CONTENTS}/Info.plist" >/dev/null 2>&1; then
    echo "ERROR: 固定要件違反 — ${forbidden} が Info.plist に存在する" >&2
    exit 1
  fi
done
echo "  (確認) NSScreenCaptureUsageDescription / NSMicrophoneUsageDescription は未設定 = 要求しない"

echo ""
echo "完成: ${APP_BUNDLE}"
echo "起動: open \"${APP_BUNDLE}\"   または   \"${MACOS_DIR}/${EXECUTABLE}\""

if [[ "${OPEN:-0}" == "1" ]]; then
  echo "==> open で起動"
  open "${APP_BUNDLE}"
fi
