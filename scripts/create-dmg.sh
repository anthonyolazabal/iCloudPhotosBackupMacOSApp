#!/bin/bash

# iCloud Photos Backup - DMG Creation Script
# This script creates a notarized DMG for distribution outside the App Store

set -e

# Configuration
APP_NAME="iCloudPhotosBackup"
BUNDLE_ID="com.icloudphotosbackup.app"
DEVELOPER_ID="Developer ID Application: Your Name (4HER27FVVT)"
TEAM_ID="4HER27FVVT"
APPLE_ID="your-apple-id@email.com"  # Your Apple Developer account email
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # Generate at appleid.apple.com

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
DMG_TEMP="$BUILD_DIR/dmg_temp"

echo "=== iCloud Photos Backup DMG Builder ==="
echo ""

# Step 1: Clean and create build directory
echo "Step 1: Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 2: Build the app in Release mode
echo "Step 2: Building app in Release configuration..."
cd "$PROJECT_DIR"
xcodebuild -project iCloudPhotosBackup.xcodeproj \
    -scheme iCloudPhotosBackup \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive

# Step 3: Export the archive
echo "Step 3: Exporting archive..."
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -exportPath "$BUILD_DIR/Export" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

cp -R "$BUILD_DIR/Export/$APP_NAME.app" "$APP_PATH"

# Step 4: Verify code signing
echo "Step 4: Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Code signature verified!"

# Step 5: Create DMG
echo "Step 5: Creating DMG..."
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TEMP"

# Step 6: Sign the DMG
echo "Step 6: Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" "$DMG_PATH"

# Step 7: Notarize the DMG
echo "Step 7: Submitting for notarization..."
echo "This may take a few minutes..."

xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

# Step 8: Staple the notarization ticket
echo "Step 8: Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# Verify stapling
xcrun stapler validate "$DMG_PATH"

echo ""
echo "=== Build Complete ==="
echo "DMG location: $DMG_PATH"
echo ""
echo "The DMG is signed and notarized, ready for distribution!"
