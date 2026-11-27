#!/usr/bin/env bash
# Wraps the SwiftPM release binary into build/fractalWM.app and signs it.
# Only produces files. It never launches the app.
# Usage: swift build -c release && scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${FRACTALWM_SIGN_IDENTITY:-fractalWM Dev}"
BUNDLE_ID="local.fractalwm"
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/fractalWM.app"

if [ ! -x "$BIN_DIR/FractalWM" ]; then
  echo "error: $BIN_DIR/FractalWM not found. Run: swift build -c release" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/FractalWM" "$APP/Contents/MacOS/FractalWM"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>fractalWM</string>
  <key>CFBundleExecutable</key><string>FractalWM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# A fixed identity keeps the VM's Accessibility grant valid across rebuilds.
# Untrusted self-signed certificates are fine, so this doesn't filter with -v.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  echo "Signed with '$IDENTITY'"
else
  echo "warning: signing identity '$IDENTITY' not found, so signing ad-hoc." >&2
  echo "         The Accessibility grant will reset after every build." >&2
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

echo "Built $APP"
