# BootHarbor

<img src="Assets/Branding/BootHarborIcon.png" width="112" alt="BootHarbor USB creator icon" />

**Windows & Linux USB Creator for macOS**

Built with love ❤️ by [Naeem Asghar](https://github.com/sirnaeemasghar).

BootHarbor creates verified Windows UEFI installation USBs and writes supported partitioned Linux/raw images. It is free, open source and independent of Rufus.

## Install

Download the latest build from [Releases](https://github.com/sirnaeemasghar/BootHarbor/releases/latest). Open the DMG and drag **BootHarbor** into Applications, or unzip the app and move it there.

Requires **macOS 14 or later**. Downloadable builds currently target **Apple Silicon (arm64)**. Intel Macs can build from source; Intel runtime compatibility has not been tested.

The community build is ad-hoc signed, not Apple notarized. macOS may block its first launch. After checking the download source, use **System Settings → Privacy & Security → Open Anyway** if offered. On managed Macs, follow your administrator’s policy.

## Create a USB

1. Back up the USB: **creation erases every partition on the selected drive**.
2. Open BootHarbor and select your Windows ISO or supported Linux ISO/IMG.
3. Select the external USB, click **Create installation USB…**, review the destination and type its identifier to confirm.
4. Approve the macOS administrator prompt. Keep the Mac connected to power and its lid open while preparation, writing and verification finish.
5. Wait for verification and safe ejection, then boot the destination computer from the USB. Windows media requires **UEFI** boot mode and a matching target architecture.

If verification succeeds but another macOS process blocks ejection, BootHarbor shows an ejection warning. Use **Eject USB** to retry; creating the media again is unnecessary.

## Features and scope

- Native SwiftUI interface with glass effects and accessibility fallbacks.
- External USB discovery, explicit erase confirmation and protection for source, app and startup volumes.
- Windows FAT32/MBR installation media, including automatic oversized WIM/ESD splitting using bundled wimlib.
- Validated MBR/GPT raw-image writing with exclusive disk access.
- SHA-256 verification of all copied Windows files and complete raw-image read-back.
- Progress, cancellation, logs, idle-sleep prevention and safe ejection.
- Buffered copying and batched synchronization before mandatory read-back verification.

Windows legacy BIOS boot code, NTFS/UEFI:NTFS, persistence, Windows To Go and ISO downloads are not implemented. Optical-only ISOs and unsafe devices are rejected. See the [feature matrix](docs/FEATURES.md).

## Build from source

Install Xcode with Swift 6 or newer and its command-line tools, then:

```sh
git clone https://github.com/sirnaeemasghar/BootHarbor.git
cd BootHarbor
./scripts/build-dependencies.sh
./scripts/package-app.sh
open Build/BootHarbor.app
```

Dependency source archives and pinned checksums are included in `Dependencies/`. Build tools and wimlib are installed inside the checkout; no global Homebrew installation is performed. The build scripts default to Xcode at `/Applications/Xcode.app`; set `DEVELOPER_DIR` for another installation.

## Tests and validation

```sh
./scripts/check-source.sh
./scripts/swift-local.sh test
./scripts/test-integration.sh
codesign --verify --deep --strict Build/BootHarbor.app
```

The integration suite uses disposable disk images, including its own 128 MB virtual disk. It does not write physical USB drives. The suite covers WIM processing, file and raw-image read-back, corruption detection, disk safety, cancellation, sleep assertions and completion handling.

A Windows 10 USB passed all **907 file-hash checks** on a real drive. A target-PC boot/install test has **not** been performed. Optimized physical-drive creation time has not been measured; speed depends on the USB, image and verification work. See [testing](docs/TESTING.md) and the [hardware test summary](docs/HARDWARE_TEST_2026-11-01.md).

## Repository layout

| Directory | Contents |
| --- | --- |
| `Sources/` | SwiftUI app, shared media engine and privileged helper |
| `Tests/` | Unit and disposable virtual-media integration tests |
| `Assets/` | App icon, portrait and icon-generation source |
| `Dependencies/` | Pinned dependency source archives and checksums |
| `scripts/` | Local dependency build, tests and packaging |
| `docs/` | Architecture, supported features and test evidence |
| `.github/` | CI and bug-report template |

Windows installation images, local hardware logs, build caches and the entire research folder are excluded. They are not needed to build or run BootHarbor.

## Bugs and contributions

Use **Report a bug** in the app to copy diagnostics and open [GitHub Issues](https://github.com/sirnaeemasghar/BootHarbor/issues). Nothing is sent automatically. Remove private paths or personal information before sharing logs. See [contribution guidance](CONTRIBUTING.md) and [security reporting](SECURITY.md).

## License

BootHarbor is **GPL-3.0-or-later**. You may use, study, modify and redistribute it under that license. See [LICENSE](LICENSE), [third-party notices](THIRD_PARTY_NOTICES.md) and [architecture](docs/ARCHITECTURE.md). Corresponding dependency sources are included.
