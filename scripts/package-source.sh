#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
scripts/check-source.sh
python3 - <<'PY'
from pathlib import Path
import hashlib,json,zipfile
root=Path.cwd()
roots=['Sources','Tests','Assets','scripts','docs','.github']
files=[root/name for name in ['Package.swift','.gitignore','LICENSE','README.md',
                              'THIRD_PARTY_NOTICES.md','CONTRIBUTING.md','SECURITY.md','CHANGELOG.md']]
for directory in roots:
    files.extend(p for p in (root/directory).rglob('*') if p.is_file() and not p.is_symlink())
files.extend(p for p in (root/'Dependencies').iterdir() if p.is_file() and not p.is_symlink())
excluded_extensions={'.iso','.img','.dmg','.wim','.swm','.esd','.vhd','.vhdx','.p12','.p8','.key','.pem'}
files=sorted(set(p for p in files if p.suffix.lower() not in excluded_extensions
                 and p.name not in {'.DS_Store','PUBLICATION_PLAN.md','GITHUB_READINESS.md'} and p.name!='fetch-rufus.sh'
                 and not p.name.startswith('.env')))
output=root/'Build'/'PublicationCandidate'
output.mkdir(parents=True,exist_ok=True)
archive=output/'BootHarbor-source.zip'
manifest=[]
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as bundle:
    for file in files:
        relative=file.relative_to(root).as_posix()
        assert not relative.startswith(('Open Source Data about Rufus/','Build/','.local/','.build/'))
        data=file.read_bytes()
        bundle.write(file,relative)
        manifest.append({'path':relative,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
(output/'source-manifest.json').write_text(json.dumps({'files':manifest,'fileCount':len(manifest),
     'archiveSHA256':hashlib.sha256(archive.read_bytes()).hexdigest(),
     'publicationStatus':'Source distribution; excludes installation media, research and local build data.'},indent=2)+'\n')
print(f'Local source candidate: {archive}')
print(f'{len(manifest)} files; Windows media, research, caches and personal logs excluded.')
PY
