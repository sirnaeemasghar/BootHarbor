#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -x .local/wimlib/bin/wimlib-imagex ]]; then
    print -u2 -- "Build dependencies first: ./scripts/build-dependencies.sh"
    exit 1
fi
scripts/generate-icon.sh
scripts/swift-local.sh build -c release
binary=$(scripts/swift-local.sh build -c release --show-bin-path)
app="$PWD/Build/BootHarbor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers" "$app/Contents/Resources/wimlib-licenses"
cp "$binary/MediaWriter" "$app/Contents/Helpers/MediaWriter"
cp .local/wimlib/bin/wimlib-imagex "$app/Contents/Helpers/wimlib-imagex"
cp Dependencies/wimlib-1.14.5/COPYING* "$app/Contents/Resources/wimlib-licenses/"
codesign --force --sign - "$app/Contents/Helpers/MediaWriter"
codesign --force --sign - "$app/Contents/Helpers/wimlib-imagex"
cp "$binary/BootHarbor" "$app/Contents/MacOS/BootHarbor"
cp Build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BootHarbor</string>
<key>CFBundleIdentifier</key><string>io.github.sirnaeemasghar.BootHarbor</string>
<key>CFBundleName</key><string>BootHarbor</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Built with love by Naeem Asghar. GPL-3.0-or-later.</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -f LICENSE ]]; then cp LICENSE "$app/Contents/Resources/LICENSE"; fi
plutil -insert ProjectRepositoryURL -string "${BOOTHARBOR_REPOSITORY_URL:-https://github.com/sirnaeemasghar/BootHarbor}" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
print -r -- "$app"
