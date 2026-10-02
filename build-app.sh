#!/usr/bin/env bash
# Собирает NetKillUI.app — двойным кликом, с иконкой, без терминала.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/netspoof"
APP="$ROOT/NetKillUI.app"

# Тулчейн Xcode (нужен для swift-testing/сборки); если нет — берётся активный.
XC="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
[ -n "$XC" ] && export DEVELOPER_DIR="$XC/Contents/Developer"

echo "▸ Сборка release…"
cd "$PKG"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "▸ Сборка бандла…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NetKillUI" "$APP/Contents/MacOS/NetKillUI"
cp "$BIN/netspoof"  "$APP/Contents/MacOS/netspoof"   # GUI ищет netspoof рядом с собой

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>netKillUI</string>
  <key>CFBundleDisplayName</key><string>netKillUI</string>
  <key>CFBundleIdentifier</key><string>com.dsavenk0.netkillui</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>NetKillUI</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo "▸ Иконка…"
PNG="/tmp/nk-icon-1024.png"
swift "$ROOT/tools/make-icon.swift" "$PNG"
ICONSET="/tmp/NetKillUI.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
sips -z 16 16   "$PNG" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   "$PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   "$PNG" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   "$PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 "$PNG" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp              "$PNG"        "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Ad-hoc подпись…"
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo ""
echo "✓ Готово: $APP"
echo "  Перетащи в /Applications или запусти двойным кликом."
echo "  Start engine внутри сам поднимет root-демон (спросит пароль)."
