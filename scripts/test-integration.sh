#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .local
fixture=$(mktemp -d "$PWD/.local/iso-fixture.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/tree/sources" "$fixture/tree/efi/boot"
touch "$fixture/tree/setup.exe" "$fixture/tree/sources/boot.wim" "$fixture/tree/sources/install.esd" "$fixture/tree/efi/boot/bootx64.efi"
# A layout fixture only: these empty files are not a Windows installer.
hdiutil makehybrid -iso -joliet -o "$fixture/layout.iso" "$fixture/tree"
MEDIA_CREATOR_TEST_ISO="$fixture/layout.iso" MEDIA_CREATOR_WIM_TOOL="$PWD/.local/wimlib/bin/wimlib-imagex" MEDIA_CREATOR_VIRTUAL_DISK_TESTS=1 scripts/swift-local.sh test "$@"
