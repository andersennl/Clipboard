#!/usr/bin/env bash
set -euo pipefail

# Builds the signed App Store package.
#
# App Store Connect rejects an upload whose build number was already used, so the build
# number is raised here rather than by hand. Every run of this script produces a package
# that is accepted; a package that was never uploaded simply leaves a gap in the numbering,
# which is harmless.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$ROOT_DIR/project.yml"
EXPORT_OPTIONS="$ROOT_DIR/Configuration/ExportOptions.plist"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="${ARCHIVE_BUILD_DIR:-/private/tmp/paste-again-archive}"
ARCHIVE_PATH="$BUILD_DIR/Paste Again.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

command -v xcodegen >/dev/null || {
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 1
}

CURRENT_BUILD="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*([0-9]+).*/\1/p' "$PROJECT_YML" | head -1)"
[ -n "$CURRENT_BUILD" ] || {
  echo "CURRENT_PROJECT_VERSION not found in $PROJECT_YML" >&2
  exit 1
}

NEXT_BUILD=$((CURRENT_BUILD + 1))
sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*)[0-9]+/\1$NEXT_BUILD/" "$PROJECT_YML"

MARKETING_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"]+)"?.*/\1/p' "$PROJECT_YML" | head -1)"
echo "Building $MARKETING_VERSION (build $NEXT_BUILD)"

xcodegen generate --spec "$PROJECT_YML" --project "$ROOT_DIR"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
xcodebuild \
  -project "$ROOT_DIR/Clipboard.xcodeproj" \
  -scheme "Paste Again" \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  -allowProvisioningUpdates

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Paste Again.app"
ARCHIVED_INFO="$ARCHIVED_APP/Contents/Info.plist"
ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARCHIVED_INFO")"
ARCHIVED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCHIVED_INFO")"

[ "$ARCHIVED_BUILD" = "$NEXT_BUILD" ] || {
  echo "Archive build mismatch: expected $NEXT_BUILD, found $ARCHIVED_BUILD" >&2
  exit 1
}

[ "$ARCHIVED_VERSION" = "$MARKETING_VERSION" ] || {
  echo "Archive version mismatch: expected $MARKETING_VERSION, found $ARCHIVED_VERSION" >&2
  exit 1
}

[ -f "$ARCHIVED_APP/Contents/Resources/AppIcon.icns" ] || {
  echo "Archive is missing AppIcon.icns" >&2
  exit 1
}

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

mkdir -p "$DIST_DIR"
PACKAGE="$DIST_DIR/Paste-Again-$MARKETING_VERSION-build$NEXT_BUILD.pkg"
cp "$EXPORT_PATH/Paste Again.pkg" "$PACKAGE"

echo
echo "Package: $PACKAGE"
pkgutil --check-signature "$PACKAGE" | sed -n '1,3p'
echo
echo "project.yml now says build $NEXT_BUILD — commit that along with the release."
