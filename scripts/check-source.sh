#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
shasum -a 256 -c Dependencies/SHA256SUMS
python3 - <<'PY'
from pathlib import Path
import sys
root=Path('.')
required=['Package.swift','LICENSE','README.md','THIRD_PARTY_NOTICES.md',
          'CONTRIBUTING.md','SECURITY.md','CHANGELOG.md','.gitignore']
missing=[p for p in required if not (root/p).is_file()]
if missing:sys.exit('Missing publication files: '+', '.join(missing))
for directory in ['Sources','Tests','Assets']:
    for source in (root/directory).rglob('*.swift'):
        if not any('SPDX-License-Identifier: GPL-3.0-or-later' in line for line in source.read_text().splitlines()[:3]):
            sys.exit('Missing source license notice: '+str(source))
for script in (root/'scripts').glob('*.sh'):
    if not script.stat().st_mode & 0o111:sys.exit('Script is not executable: '+str(script))
print('Source notices and bundled dependency checksums verified.')
PY
for script in scripts/*.sh; do zsh -n "$script"; done
