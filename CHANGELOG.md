# Changelog

## 0.4.1 — community release

- Replace the icon download badge with a USB flash drive.
- Remove internal approval wording from bug reporting and link directly to GitHub Issues.
- Add public installation, usage and source-build instructions.


## 0.4.0 — BootHarbor community build

- Approved BootHarbor name and Naeem Asghar portrait app icon.
- Native Liquid Glass on supported macOS versions; frosted and reduced-transparency fallbacks.
- Neutral version badge, privacy-safe Report a bug sheet and GitHub credit footer.
- CI, contributor/security guidance and allow-listed source-only packaging.
- Windows installation images and the complete local research folder excluded from publication.
- Retained-source raw-image probing and fail-closed cyclic ancestry checks; 30 tests pass.

## 0.3.0 — development preview

- Preserve verified-media success when source cleanup or safe ejection fails.
- Retry ordinary busy ejection at most three times; provide a separate Eject USB action.
- Copy with 4 MiB buffers, defer file synchronization until the read-back pass,
  reuse the disk-service connection, and throttle large-file progress updates.
- Keep all source/destination hash checks and live device-identity checks.
- Prevent idle system sleep during preparation, writing and verification using
  scoped IOPM assertions; release the assertion after the operation.
- Show file counts and distinguish flushing/verification progress.
- Pass 29 automated integration tests on the development Mac. Optimized real-USB
  timing and target-PC boot compatibility remain unverified.

## 0.2.0 — initial writing engine

- Windows FAT32/MBR file-copy pipeline, WIM splitting and ESD conversion fallback.
- Validated MBR/GPT raw-image writing, exclusive disk access and SHA-256 read-back.
- Correct macOS WholeDisk/WritableMedia discovery, erase confirmation and source-volume protection.
- Real Windows 10 USB run passed all 907 file-hash checks; Spotlight blocked the final eject.

## 0.1.0 — initial prototype

- Native SwiftUI device discovery, read-only image inspection and checksums.
