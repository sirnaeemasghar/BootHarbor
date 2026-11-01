#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.local/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.local/swift-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
exec swift "$@" --scratch-path Build --cache-path .local/swiftpm-cache --config-path .local/swiftpm-config --security-path .local/swiftpm-security
