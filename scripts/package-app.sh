#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/JustChat.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LOCAL_CODESIGN_KEYCHAIN="$HOME/Library/Application Support/JustChat/CodeSigning/JustChatLocal.keychain-db"

ORIGINAL_USER_KEYCHAINS=()
while IFS= read -r keychain; do
  [[ -n "$keychain" ]] && ORIGINAL_USER_KEYCHAINS+=("$keychain")
done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"//; s/"$//')

restore_user_keychains() {
  if [[ ${#ORIGINAL_USER_KEYCHAINS[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${ORIGINAL_USER_KEYCHAINS[@]}" >/dev/null
  fi
}

use_local_codesign_keychain() {
  local keychains=("$LOCAL_CODESIGN_KEYCHAIN")
  local keychain

  for keychain in "${ORIGINAL_USER_KEYCHAINS[@]}"; do
    if [[ "$keychain" != "$LOCAL_CODESIGN_KEYCHAIN" ]]; then
      keychains+=("$keychain")
    fi
  done

  security list-keychains -d user -s "${keychains[@]}" >/dev/null
}

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/arm64-apple-macosx/release/JustChat" "$MACOS_DIR/JustChat"

if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" && -f "$ROOT_DIR/scripts/generate-app-icon.swift" ]]; then
  (cd "$ROOT_DIR" && swift scripts/generate-app-icon.swift >/dev/null)
fi

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>JustChat</string>
  <key>CFBundleIdentifier</key>
  <string>com.justchat.app</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Just Chat</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Just Chat.</string>
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"
elif CODESIGN_IDENTITY="$("$ROOT_DIR/scripts/ensure-local-codesign-identity.sh")"; then
  use_local_codesign_keychain
  trap restore_user_keychains EXIT
  codesign --force --deep --options runtime --keychain "$LOCAL_CODESIGN_KEYCHAIN" --sign "$CODESIGN_IDENTITY" "$APP_DIR"
  trap - EXIT
  restore_user_keychains
else
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "$APP_DIR"
