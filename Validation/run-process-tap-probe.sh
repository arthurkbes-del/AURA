#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/P1/ProcessTapProbe.app/Contents/MacOS evidence/p1
cat > build/P1/ProcessTapProbe.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.evoluere.aura.tap-probe</string>
<key>CFBundleName</key><string>AURA Tap Probe</string>
<key>CFBundleExecutable</key><string>ProcessTapProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>Validate local processing of a controlled test tone using a private Core Audio tap. No microphone or audio recording file is used.</string>
</dict></plist>
PLIST
swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 Validation/ProcessTapProbe.swift -o build/P1/ProcessTapProbe.app/Contents/MacOS/ProcessTapProbe
swiftc -swift-version 6 -parse-as-library -target x86_64-apple-macos15.0 Validation/ProcessTapProbe.swift -o build/P1/ProcessTapProbe-x86_64
codesign --force --sign - --timestamp=none build/P1/ProcessTapProbe.app
if [[ "${1:-}" != "--compile-only" ]]; then
    build/P1/ProcessTapProbe.app/Contents/MacOS/ProcessTapProbe
fi
