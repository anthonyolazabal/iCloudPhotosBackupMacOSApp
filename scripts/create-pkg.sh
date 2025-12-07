#!/bin/bash

# iCloud Photos Backup - PKG Installer Creation Script
# Creates a signed and notarized PKG installer

set -e

# Configuration
APP_NAME="iCloudPhotosBackup"
BUNDLE_ID="com.icloudphotosbackup.app"
VERSION="1.0.0"
DEVELOPER_ID_APP="Developer ID Application: Your Name (4HER27FVVT)"
DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (4HER27FVVT)"
TEAM_ID="4HER27FVVT"
APPLE_ID="your-apple-id@email.com"
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
PKG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.pkg"
PKG_TEMP="$BUILD_DIR/pkg_temp"

echo "=== iCloud Photos Backup PKG Builder ==="
echo ""

# Step 1: Clean and create build directory
echo "Step 1: Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 2: Build the app
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

# Step 4: Create PKG installer
echo "Step 4: Creating PKG installer..."
rm -rf "$PKG_TEMP"
mkdir -p "$PKG_TEMP/payload/Applications"
cp -R "$APP_PATH" "$PKG_TEMP/payload/Applications/"

# Create component plist
pkgbuild --analyze --root "$PKG_TEMP/payload" "$BUILD_DIR/component.plist"

# Build the component package
pkgbuild --root "$PKG_TEMP/payload" \
    --component-plist "$BUILD_DIR/component.plist" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    "$BUILD_DIR/component.pkg"

# Create distribution XML
cat > "$BUILD_DIR/distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>iCloud Photos Backup</title>
    <organization>com.icloudphotosbackup</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
    <welcome file="welcome.html"/>
    <license file="license.html"/>
    <conclusion file="conclusion.html"/>
    <pkg-ref id="$BUNDLE_ID"/>
    <choices-outline>
        <line choice="default">
            <line choice="$BUNDLE_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$BUNDLE_ID" visible="false">
        <pkg-ref id="$BUNDLE_ID"/>
    </choice>
    <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
EOF

# Create resources directory with installer pages
mkdir -p "$BUILD_DIR/resources"

cat > "$BUILD_DIR/resources/welcome.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }
        h1 { color: #007AFF; }
    </style>
</head>
<body>
    <h1>iCloud Photos Backup</h1>
    <p>Welcome to the iCloud Photos Backup installer.</p>
    <p>This application allows you to back up your iCloud Photos to S3-compatible cloud storage or SMB network shares.</p>
    <p><strong>Features:</strong></p>
    <ul>
        <li>Secure AES-256 encryption</li>
        <li>Incremental backups with deduplication</li>
        <li>Scheduled automatic backups</li>
        <li>Integrity verification</li>
    </ul>
    <p>Click Continue to proceed with the installation.</p>
</body>
</html>
EOF

cat > "$BUILD_DIR/resources/license.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; font-size: 12px; }
    </style>
</head>
<body>
    <h2>License Agreement</h2>
    <p>Copyright (c) 2024 Anthony Olazabal</p>
    <p>Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:</p>
    <p>The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.</p>
    <p>THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.</p>
</body>
</html>
EOF

cat > "$BUILD_DIR/resources/conclusion.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }
        h1 { color: #34C759; }
    </style>
</head>
<body>
    <h1>Installation Complete</h1>
    <p>iCloud Photos Backup has been installed successfully.</p>
    <p>You can find the application in your Applications folder.</p>
    <p>To get started:</p>
    <ol>
        <li>Open iCloud Photos Backup from Applications</li>
        <li>Grant Photos library access when prompted</li>
        <li>Configure your backup destination (S3 or SMB)</li>
        <li>Start your first backup!</li>
    </ol>
    <p>Thank you for using iCloud Photos Backup!</p>
</body>
</html>
EOF

# Build the product archive
productbuild --distribution "$BUILD_DIR/distribution.xml" \
    --resources "$BUILD_DIR/resources" \
    --package-path "$BUILD_DIR" \
    "$BUILD_DIR/unsigned.pkg"

# Step 5: Sign the PKG
echo "Step 5: Signing PKG installer..."
productsign --sign "$DEVELOPER_ID_INSTALLER" \
    "$BUILD_DIR/unsigned.pkg" \
    "$PKG_PATH"

rm "$BUILD_DIR/unsigned.pkg"

# Step 6: Notarize the PKG
echo "Step 6: Submitting for notarization..."
xcrun notarytool submit "$PKG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

# Step 7: Staple the notarization ticket
echo "Step 7: Stapling notarization ticket..."
xcrun stapler staple "$PKG_PATH"

# Cleanup
rm -rf "$PKG_TEMP"
rm -f "$BUILD_DIR/component.pkg"
rm -f "$BUILD_DIR/component.plist"

echo ""
echo "=== Build Complete ==="
echo "PKG location: $PKG_PATH"
echo ""
echo "The PKG installer is signed and notarized, ready for distribution!"
