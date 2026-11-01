#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p Build .local/icon-module-cache
xcrun swift -module-cache-path "$PWD/.local/icon-module-cache" Assets/AppIcon.swift "$PWD/Build/AppIcon.iconset" "$PWD/Assets/Branding/BootHarborIcon.png"
iconutil -c icns Build/AppIcon.iconset -o Build/AppIcon.icns
