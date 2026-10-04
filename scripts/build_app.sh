#!/usr/bin/env bash
set -euo pipefail

# Directory of the project root
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="HardyFlow.app"
APP_DIR="${BUILD_DIR}/${APP_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🎙️ [1/4] Compiling HardyFlow in release mode..."
cd "${PROJECT_DIR}"
swift build -c release --product HardyFlow

BINARY_PATH="$(swift build -c release --show-bin-path)/HardyFlow"

if [ ! -f "${BINARY_PATH}" ]; then
    echo "❌ Error: Binary not found at ${BINARY_PATH}"
    exit 1
fi

echo "📦 [2/4] Assembling macOS Application Bundle (${APP_NAME})..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BINARY_PATH}" "${MACOS_DIR}/HardyFlow"
chmod +x "${MACOS_DIR}/HardyFlow"

# Copy Icon and Logo Assets
if [ -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "${PROJECT_DIR}/Resources/app_logo.png" ]; then
    cp "${PROJECT_DIR}/Resources/app_logo.png" "${RESOURCES_DIR}/app_logo.png"
fi

echo "📝 [3/4] Generating App Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HardyFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.hardyflow.mac</string>
    <key>CFBundleName</key>
    <string>HardyFlow</string>
    <key>CFBundleDisplayName</key>
    <string>HardyFlow</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>HardyFlow requires microphone access to record your speech for real-time dictation into any application.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>HardyFlow requires speech recognition permission to transcribe your speech on-device with zero server latency.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>HardyFlow uses accessibility features to paste transcribed text directly into your active background applications.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>HardyFlow uses Apple Events to support fallback direct pasting into external applications.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

echo "🔏 [4/4] Applying macOS code signature with audio entitlements and persistent designated requirement..."
ENTITLEMENTS="${PROJECT_DIR}/Resources/HardyFlow.entitlements"
codesign -s - --force --deep --entitlements "${ENTITLEMENTS}" -r '=designated => identifier "com.hardyflow.mac"' "${APP_DIR}"

if [ -w "/Applications" ]; then
    echo "📲 Updating /Applications/HardyFlow.app..."
    rm -rf "/Applications/HardyFlow.app"
    cp -R "${APP_DIR}" "/Applications/HardyFlow.app"
    codesign -s - --force --deep --entitlements "${ENTITLEMENTS}" -r '=designated => identifier "com.hardyflow.mac"' "/Applications/HardyFlow.app"
    
    # Clean up legacy Wisperflow.app if present
    if [ -d "/Applications/Wisperflow.app" ]; then
        rm -rf "/Applications/Wisperflow.app"
    fi
fi

echo "✨ HardyFlow Build complete!"
echo "--------------------------------------------------------"
echo "Application bundle created at:"
echo "  ${APP_DIR}"
echo ""
echo "To launch HardyFlow:"
echo "  open \"${APP_DIR}\""
echo ""
echo "Installed to /Applications/HardyFlow.app (if permissions allowed)"
echo "--------------------------------------------------------"
