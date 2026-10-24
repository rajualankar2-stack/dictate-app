#!/bin/bash
# Build /tmp/PasteTarget.app from scripts/paste_target.swift.
# An app bundle, not a bare binary: a bare binary cannot take keyboard focus,
# so the Dictate paste would never land in its text view.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
A=/tmp/PasteTarget.app
rm -rf "$A"; mkdir -p "$A/Contents/MacOS"
swiftc -O -o "$A/Contents/MacOS/PasteTarget" scripts/paste_target.swift
cat > "$A/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PasteTarget</string>
<key>CFBundleIdentifier</key><string>com.raj.dictate.pastetarget</string>
<key>CFBundleName</key><string>PasteTarget</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
codesign --force --sign - "$A" >/dev/null 2>&1
echo "built $A"
