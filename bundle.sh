#!/bin/bash
# bundle.sh — package the release binary into GhostOverlay.app and ad-hoc codesign it.
set -euo pipefail
cd "$(dirname "$0")"

BINARY=.build/release/Cloak
if [ ! -f "$BINARY" ]; then
  echo "release binary not found; run: swift build -c release" >&2
  exit 1
fi

APP=Cloak.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Cloak"
cp Cloak.icns "$APP/Contents/Resources/Cloak.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Cloak</string>
	<key>CFBundleIdentifier</key>
	<string>com.cloak.app</string>
	<key>CFBundleName</key>
	<string>Cloak</string>
	<key>CFBundleDisplayName</key>
	<string>Cloak</string>
	<key>CFBundleIconFile</key>
	<string>Cloak</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>GhostOverlay uses the microphone for push-to-talk dictation of your questions.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>GhostOverlay transcribes your dictated questions using speech recognition.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>GhostOverlay transcribes system audio so it can answer questions about your conversations.</string>
</dict>
</plist>
EOF

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Prefer a stable signing identity so macOS TCC grants (mic/speech/accessibility)
# survive rebuilds; ad-hoc signatures change every build and invalidate grants.
IDENTITY=""
for candidate in "Developer ID Application" "GhostOverlay Dev" "Apple Development"; do
  MATCH=$(security find-identity -v -p codesigning | grep "\"$candidate" | head -1 | sed 's/.*"\(.*\)"/\1/')
  if [ -n "$MATCH" ]; then IDENTITY="$MATCH"; break; fi
done

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  cat <<'NOTE'
note: signed ad-hoc — macOS will re-ask permissions after each rebuild.
To make grants persist, create a self-signed "GhostOverlay Dev" codesigning certificate:
  Keychain Access → Certificate Assistant → Create a Certificate →
  Name: GhostOverlay Dev, Type: Code Signing → Create. Then rerun bundle.sh.
NOTE
fi
echo "Built and signed: $APP"
