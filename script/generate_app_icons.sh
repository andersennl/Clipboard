#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/Design/Brand/Final/clipboard-app-store-1024.png"
APP_ICON_SET="$ROOT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
ICNS_OUTPUT="$ROOT_DIR/Resources/AppIcon.icns"
TEMP_ASSET_OUTPUT="$(mktemp -d /private/tmp/clipboard-icons.XXXXXX)"

cleanup() {
  rm -rf "$TEMP_ASSET_OUTPUT"
}
trap cleanup EXIT

mkdir -p "$APP_ICON_SET"

render_icon() {
  local size="$1"
  local filename="$2"

  sips --resampleHeightWidth "$size" "$size" "$SOURCE_ICON" \
    --out "$APP_ICON_SET/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

xcrun actool "$ROOT_DIR/Resources/Assets.xcassets" \
  --compile "$TEMP_ASSET_OUTPUT" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --target-device mac \
  --app-icon AppIcon \
  --output-partial-info-plist "$TEMP_ASSET_OUTPUT/asset-info.plist" \
  --warnings \
  --errors \
  >/dev/null

cp "$TEMP_ASSET_OUTPUT/AppIcon.icns" "$ICNS_OUTPUT"
