# Third-party notices

## Rufus reference

Rufus (https://github.com/pbatard/rufus) was studied as separate research. The local research folder and its archives are not part of this repository or app package. No Rufus Windows executable or formatting component is linked into this macOS application. This project does not claim official affiliation or use Rufus branding.

## wimlib 1.14.5

Upstream/source: https://wimlib.net/downloads/wimlib-1.14.5.tar.gz
Local source archive: `Dependencies/wimlib-1.14.5.tar.gz`.
Copyright and terms: see the archive's `COPYING`, `COPYING.GPLv3`, `COPYING.LGPL` and per-file notices. wimlib-imagex is distributed here under GPL-3.0-or-later. The library's optional dual licensing is described by its own COPYING file.

Built with `--without-ntfs-3g --without-fuse --disable-shared --enable-static`. The bundled wimlib-imagex binary statically includes libwim and dynamically links only Apple's system library on the current host. Its license texts are copied to the app's `Contents/Resources/wimlib-licenses`. Corresponding source archive and the exact local build script are included in this project. No globally installed wimlib is required.

## pkgconf 2.5.1 — build-time only

Upstream: https://github.com/pkgconf/pkgconf
Release distribution: https://distfiles.ariadne.space/pkgconf/
Retrieved gzip release archive from the MacPorts mirror: https://distfiles.macports.org/pkgconf/pkgconf-2.5.1.tar.gz
Local source: `Dependencies/pkgconf-2.5.1.tar.gz`, including COPYING and per-file notices.

pkgconf is built locally only to satisfy wimlib's build configuration. It is not bundled in the app. Preserve all of its source license and copyright notices when redistributing the source archive.

Dependency archive SHA-256 values are pinned in `Dependencies/SHA256SUMS`. These record the retrieved release bytes; they are not a claim that an independent detached-signature verification has been performed.
