#!/usr/bin/env bash
#
# make_app.sh — swift build -c release --arch arm64 の実行ファイルを .app バンドルに組み立て、
# ad-hoc 署名し、他の Apple Silicon Mac に渡せる .pkg / .zip を生成する。
#
# 目的: bare executable では TCC（音声キャプチャ）ダイアログが不安定なため、
#       .app バンドル + 署名でバンドル識別 + Info.plist を LaunchServices/TCC に正しく認識させる。
#
# 固定要件: TCC は音声キャプチャ権限のみ（NSAudioCaptureUsageDescription）。
#           画面収録・マイク権限は要求しない（Info.plist にキーを追加しない）。
#
# 使い方:
#   scripts/make_app.sh            # arm64 release ビルド → .app 生成 → ad-hoc 署名 → .pkg/.zip 生成 → 検証
#   OPEN=1 scripts/make_app.sh     # 生成後に open で起動
#
# 出力:
#   build/SpeechTap.app
#   build/SpeechTap-arm64.pkg       # /Applications にインストールする unsigned pkg
#   build/SpeechTap-arm64.app.zip   # .app を直接コピーしたい場合の zip
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
ARCH="arm64"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
COMPONENT_PKG_PATH="${BUILD_DIR}/${APP_NAME}-${ARCH}-component.pkg"
PKG_PATH="${BUILD_DIR}/${APP_NAME}-${ARCH}.pkg"
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${ARCH}.app.zip"

INFO_PLIST_SRC="${ROOT_DIR}/Sources/SpeechTapApp/Resources/Info.plist"
CONFIG_DEFAULT_SRC="${ROOT_DIR}/Sources/SpeechTapApp/Resources/config.default.conf"
INSTALLER_DISTRIBUTION="${ROOT_DIR}/scripts/installer/distribution.dist"
ENTITLEMENTS="${BUILD_DIR}/${APP_NAME}.entitlements"
BUNDLE_IDENTIFIER="com.example.speech-tap"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST_SRC}" 2>/dev/null || echo "0.1.0")"
BUILD_FLAGS=(-c release --arch "${ARCH}")

echo "==> 1/7 ${ARCH} release ビルド"
swift build "${BUILD_FLAGS[@]}"
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
EXEC_SRC="${BIN_PATH}/${EXECUTABLE}"
if [[ ! -x "${EXEC_SRC}" ]]; then
  echo "ERROR: 実行ファイルが見つからない: ${EXEC_SRC}" >&2
  exit 1
fi
BIN_ARCHES="$(/usr/bin/lipo -archs "${EXEC_SRC}")"
if [[ "${BIN_ARCHES}" != "${ARCH}" ]]; then
  echo "ERROR: ${EXECUTABLE} が ${ARCH} 専用ではありません: ${BIN_ARCHES}" >&2
  exit 1
fi

echo "==> 2/7 .app バンドル構造を構築: ${APP_BUNDLE}"
# 生成物（build/SpeechTap.app）のみクリーンアップ。ソースには触れない。
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 実行ファイル（CFBundleExecutable と一致させる）。
cp "${EXEC_SRC}" "${MACOS_DIR}/${EXECUTABLE}"
chmod +x "${MACOS_DIR}/${EXECUTABLE}"
APP_ARCHES="$(/usr/bin/lipo -archs "${MACOS_DIR}/${EXECUTABLE}")"
if [[ "${APP_ARCHES}" != "${ARCH}" ]]; then
  echo "ERROR: .app 内の実行ファイルが ${ARCH} 専用ではありません: ${APP_ARCHES}" >&2
  exit 1
fi

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

echo "==> 3/7 entitlements 生成（音声キャプチャ用・最小）"
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

echo "==> 4/7 ad-hoc 署名（codesign -s -）"
# --force: 再署名を許可。--options なし = Hardened Runtime 無効（ローカル検証用）。
# entitlements を埋め込んで署名する。
codesign --force --sign - \
  --entitlements "${ENTITLEMENTS}" \
  --identifier "${BUNDLE_IDENTIFIER}" \
  "${APP_BUNDLE}"

echo "==> 4.5/7 配布不要な拡張属性を除去"
xattr -cr "${APP_BUNDLE}"

echo "==> 5/7 検証"
echo "--- codesign --verify ---"
codesign --verify --verbose=2 "${APP_BUNDLE}"
echo "--- 実行ファイルアーキテクチャ ---"
echo "  ${EXECUTABLE} = $(/usr/bin/lipo -archs "${MACOS_DIR}/${EXECUTABLE}")"
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

echo "==> 6/7 インストーラ pkg 生成: ${PKG_PATH}"
rm -f "${COMPONENT_PKG_PATH}" "${PKG_PATH}"
COPYFILE_DISABLE=1 pkgbuild \
  --component "${APP_BUNDLE}" \
  --install-location "/Applications" \
  --identifier "${BUNDLE_IDENTIFIER}.component" \
  --version "${VERSION}" \
  "${COMPONENT_PKG_PATH}"

productbuild \
  --distribution "${INSTALLER_DISTRIBUTION}" \
  --package-path "${BUILD_DIR}" \
  "${PKG_PATH}"
rm -f "${COMPONENT_PKG_PATH}"

echo "==> 7/7 .app zip 生成: ${ZIP_PATH}"
rm -f "${ZIP_PATH}"
(
  cd "${BUILD_DIR}"
  zip -qry -X "$(basename "${ZIP_PATH}")" "$(basename "${APP_BUNDLE}")"
)

echo ""
echo "完成: ${APP_BUNDLE}"
echo "インストーラ: ${PKG_PATH}"
echo "直接配布 zip: ${ZIP_PATH}"
echo "起動: open \"${APP_BUNDLE}\"   または   \"${MACOS_DIR}/${EXECUTABLE}\""
echo "他の Mac では ${PKG_PATH} をインストール後、/Applications/${APP_NAME}.app をダブルクリックして起動できます。"

if [[ "${OPEN:-0}" == "1" ]]; then
  echo "==> open で起動"
  open "${APP_BUNDLE}"
fi
