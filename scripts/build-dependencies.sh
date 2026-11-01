#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
project="$PWD"
shasum -a 256 -c Dependencies/SHA256SUMS
[[ -f Dependencies/pkgconf-2.5.1/configure ]] || tar -xzf Dependencies/pkgconf-2.5.1.tar.gz -C Dependencies
[[ -f Dependencies/wimlib-1.14.5/configure ]] || tar -xzf Dependencies/wimlib-1.14.5.tar.gz -C Dependencies
# Libtool cannot build reliably under a path containing spaces. This temporary
# alias has no spaces; all source, build and installed files remain in the project.
alias_root="/private/tmp/media-creator-deps-$(uuidgen)"
ln -s "$project" "$alias_root"
trap 'rm -f "$alias_root"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CC="$(xcrun --find clang)"
export SDKROOT="$(xcrun --show-sdk-path)"
cd "$alias_root/Dependencies/pkgconf-2.5.1"
./configure --prefix="$alias_root/.local/pkgconf" --disable-shared --enable-static
make -j4
make install
cd "$alias_root/Dependencies/wimlib-1.14.5"
PKG_CONFIG="$alias_root/.local/pkgconf/bin/pkgconf" ./configure --prefix="$alias_root/.local/wimlib" --without-ntfs-3g --without-fuse --disable-shared --enable-static
make -j4
make install
"$project/.local/wimlib/bin/wimlib-imagex" --version
