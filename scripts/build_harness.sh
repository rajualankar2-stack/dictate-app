#!/bin/bash
# Build /tmp/GuiHarness.app from scripts/gui_harness.swift so it launches frontmost (a bare binary cannot take focus).
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
A=/tmp/GuiHarness.app
rm -rf $A; mkdir -p $A/Contents/MacOS
swiftc -O -o $A/Contents/MacOS/GuiHarness scripts/gui_harness.swift
cat > $A/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GuiHarness</string>
<key>CFBundleIdentifier</key><string>com.raj.dictate.guiharness</string>
<key>CFBundleName</key><string>GuiHarness</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
codesign --force --sign - $A >/dev/null 2>&1
echo built $A
