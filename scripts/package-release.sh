#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
scripts/package-app.sh
scripts/package-source.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Build/BootHarbor.app/Contents/Info.plist)
release="$PWD/Build/Release"
staging="$PWD/Build/DMGContents"
mkdir -p "$release" "$staging"
ditto Build/BootHarbor.app "$staging/BootHarbor.app"
ln -sfn /Applications "$staging/Applications"
cp LICENSE "$staging/LICENSE.txt"
print -r -- 'Drag BootHarbor into Applications. Requires macOS 14+. Community build: ad-hoc signed, not notarized. See the GitHub README for first-launch instructions.' > "$staging/INSTALL.txt"
name="BootHarbor-${version}-macOS-$(uname -m)"
ditto -c -k --sequesterRsrc --keepParent Build/BootHarbor.app "$release/$name.zip"
hdiutil create -volname BootHarbor -srcfolder "$staging" -ov -format UDZO "$release/$name.dmg"
cp Build/PublicationCandidate/BootHarbor-source.zip "$release/BootHarbor-${version}-source.zip"
(cd "$release" && shasum -a 256 *.zip *.dmg > SHA256SUMS)
codesign --verify --deep --strict Build/BootHarbor.app
print -r -- "$release"
