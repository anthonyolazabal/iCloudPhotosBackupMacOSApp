#!/bin/bash

# iCloud Photos Backup - Simple DMG Creation (No Notarization)
# Use this for testing. Users will need to right-click > Open the first time.

set -e

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="iCloudPhotosBackup"
DMG_TEMP="$BUILD_DIR/dmg_temp"

echo "=== iCloud Photos Backup - Simple DMG Builder ==="
echo ""

# Step 1: Create build directory
echo "Step 1: Preparing build directory..."
mkdir -p "$BUILD_DIR"

# Step 2: Build the app
echo "Step 2: Building app in Release configuration..."
cd "$PROJECT_DIR"

xcodebuild -project iCloudPhotosBackup.xcodeproj \
    -scheme iCloudPhotosBackup \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build

# Find the built app
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "*.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app"
    exit 1
fi

echo "Found app at: $APP_PATH"

# Step 3: Create DMG
echo "Step 3: Creating DMG..."
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Remove old DMG if exists
rm -f "$BUILD_DIR/$APP_NAME.dmg"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$BUILD_DIR/$APP_NAME.dmg"

rm -rf "$DMG_TEMP"

echo ""
echo "=== Build Complete ==="
echo "DMG location: $BUILD_DIR/$APP_NAME.dmg"
echo ""
echo "NOTE: This DMG is NOT notarized."
echo "Users will need to right-click the app and select 'Open' the first time."
echo ""
echo "For production distribution, use create-dmg.sh with notarization."
