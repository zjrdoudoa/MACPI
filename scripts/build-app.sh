#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${MACPI_BUILD_DIR:-/private/tmp/macpi-build}"
APP_DIR="$ROOT_DIR/dist/MACPI.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/assets/AppIconSource.png"
ICON_BUILD_DIR="$BUILD_DIR/icon"
ICON_MASTER="$ICON_BUILD_DIR/AppIcon-master.png"
ICONSET_DIR="$ICON_BUILD_DIR/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c release --product macpi --product macpi-gui

rm -rf "$APP_DIR"
rm -rf "$ICON_BUILD_DIR"
install -d -m 0755 "$MACOS_DIR" "$RESOURCES_DIR"
install -m 0755 ".build/release/macpi-gui" "$MACOS_DIR/MACPI"
install -m 0755 ".build/release/macpi" "$RESOURCES_DIR/macpi"

if [ -f "$ICON_SOURCE" ]; then
  install -d -m 0755 "$ICONSET_DIR"
  swift "$ROOT_DIR/scripts/build-app-icon.swift" "$ICON_SOURCE" "$ICON_MASTER"
  sips -z 16 16 "$ICON_MASTER" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_MASTER" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_MASTER" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_MASTER" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_MASTER" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_MASTER" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_MASTER" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_MASTER" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_MASTER" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_MASTER" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil --convert icns --output "$ICON_FILE" "$ICONSET_DIR"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MACPI</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.macpi.gui</string>
  <key>CFBundleName</key>
  <string>MACPI</string>
  <key>CFBundleDisplayName</key>
  <string>MACPI</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
echo "Built $APP_DIR"
