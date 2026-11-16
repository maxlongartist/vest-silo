#!/bin/zsh
set -eu
cd "${0:A:h}"
app="Vest Silo.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
icon_work=$(mktemp -d)
trap 'rm -rf "$icon_work"' EXIT
iconset="$icon_work/VestIsland.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" art/icon128.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" art/icon128.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$app/Resources/VestIsland.icns" "$iconset"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VestIsland</string>
<key>CFBundleIdentifier</key><string>local.vest.island.standalone</string>
<key>CFBundleName</key><string>Vest Silo</string>
<key>CFBundleIconFile</key><string>VestIsland.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleShortVersionString</key><string>1.0.4</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
cp source/session.js "$app/Resources/session.js"
if [[ "${1:-}" == "--universal" ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" source/main.swift -o "$icon_work/VestIsland-$arch"
  done
  lipo -create "$icon_work/VestIsland-arm64" "$icon_work/VestIsland-x86_64" -output "$app/MacOS/VestIsland"
else
  swiftc -O -target "$(uname -m)-apple-macos13.0" source/main.swift -o "$app/MacOS/VestIsland"
fi
codesign --force --sign - "Vest Silo.app"
