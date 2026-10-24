#!/bin/bash
# Build Dictate.app into build/ (inside the project; nothing is installed or registered).
# Signs with the stable Apple Development certificate so the Accessibility grant survives rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IDENTITY="${DICTATE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || { echo "No Apple Development certificate found; set DICTATE_SIGN_IDENTITY"; exit 1; }

swift build -c release 2>&1 | tee /tmp/build.log | grep -E "error|warning: unre|Compiling|Build complete"
if grep -q "error:" /tmp/build.log; then echo "BUILD FAILED"; exit 1; fi
BIN=.build/release/Dictate
[ -x "$BIN" ] || { echo "build failed: $BIN missing"; exit 1; }

APP=build/Dictate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dictate"

# Feedback sounds (all packs)
for f in Resources/Sounds/sound_*.wav; do cp "$f" "$APP/Contents/Resources/$(basename "$f")"; done

# App icon: draw the 1024 master, scale to the ten macOS sizes, pack as .icns
ICONTMP=$(mktemp -d)
swiftc -O scripts/make_icon.swift -o "$ICONTMP/make_icon" 2>&1 | grep -E "error" || true
"$ICONTMP/make_icon" "$ICONTMP/master.png" >/dev/null
SET="$ICONTMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONTMP/master.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONTMP/master.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONTMP"
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || { echo "icon build failed"; exit 1; }

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Dictate</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.raj.dictate</string>
  <key>CFBundleName</key><string>Dictate</string>
  <key>CFBundleDisplayName</key><string>Dictate</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Dictate records your voice while you hold the hotkey, then transcribes it on this Mac.</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if codesign --force --sign "$IDENTITY" "$APP" 2>build/codesign.err; then
  echo "signed with: $IDENTITY"
else
  echo "signing with the Apple Development identity failed:"; cat build/codesign.err
  echo "falling back to ad-hoc (Accessibility will need re-granting after each rebuild)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP" 2>&1 | tail -2
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|Signature|TeamIdentifier" | head -4
echo "built: $PWD/$APP"
