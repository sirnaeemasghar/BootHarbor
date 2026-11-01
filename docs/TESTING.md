# Test evidence

Run `./scripts/swift-local.sh test` for ordinary unit tests. Run `./scripts/test-integration.sh` after building dependencies for the complete integration suite.

The integration suite generates a synthetic Windows-layout ISO, captures a real small WIM, splits/verifies/reapplies that WIM, and creates a disposable 128 MB disk-image device. The disk test checks its virtual transport/size before formatting, creates an MBR/FAT32 filesystem, copies and verifies fixture files, resolves its backing physical storage, claims/unmounts it with Disk Arbitration, writes a partitioned raw fixture through its raw character-device node, and verifies SHA-256 read-back. It detaches and deletes its own scratch image afterward. Production USB eligibility is never relaxed by a test flag.

Coverage also includes real macOS WholeDisk/WritableMedia fields, internal/read-only/partition/non-USB rejection, incomplete metadata, undersized destinations, Windows layout detection, oversized WIM/ESD handling, source symlink refusal, target symlink refusal, existing-file refusal, startup/source-volume ancestry resolution, bounded raw partition entries, GPT CRC checks, known SHA-256, exact source-length verification and cancellation before raw writes.

The initial complete integration run passed 21 tests; the version 0.3 run described below passes 29 tests. The complete suite's latest output is in `Build/integration-tests.log`. Do not interpret passing fixture tests as proof of PC bootability or compatibility with every ISO. The synthetic ISO contains placeholder Windows filenames, not an actual installer.

## Not yet tested

- Physical interruption/hot unplug during erasure/copy, unreliable controllers or fake capacities. The Windows authorization/format/copy/verify path has now been exercised on the real USB.
- Real Windows 8/8.1/10/11 WIM/ESD combinations, large solid ESD conversion, and setup completion.
- Real Linux ISO booting, target firmware/architecture and Secure Boot combinations.
- Intel host runtime, macOS 14 runtime, distribution signing and notarization.

The earlier development app's image picker/inspection was exercised through the native UI. The latest app bundle contains the writing engine and its Create installation USB button was verified in the native UI. The corrected discovery detected an approximately 16 GB external physical USB. A subsequently authorized Windows 10 run reformatted it and passed all 907 file-hash checks; Spotlight blocked only the final safe ejection. PC boots and the optimized version’s real-USB performance remain unverified.

Record exact ISO SHA-256/source URL, target PC/architecture/firmware settings, host macOS/architecture, USB model/capacity, selected strategy and logs for every hardware boot test. Use backed-up sacrificial media for destructive testing.

## Version 0.3 regression run

The current full integration suite passes **29 tests, zero failures, no skips** (`Build/performance-fix-integration.log`). It includes the deferred flush/read-back path on FAT32 with 132 files, fresh identity checks through a reused session, deliberate output corruption rejection, persistent/transient Spotlight ejection dissent, source-detach failure, and actual IOPM assertion creation/cleanup. The 132-file virtual-disk copy/read-back took about 1.01 seconds on this host; this is a small synthetic test, not a speed forecast for physical USB media.

The physical Windows 10 run is documented in HARDWARE_TEST_2026-11-01.md. That prior run verified all files and encountered an ejection-only Spotlight dissent. The version 0.3 fixes were tested without rewriting that USB. No 5–10 minute physical USB timing or target-PC boot success has been established.

## Version 0.4.1 final validation

The complete integration suite passed **30 tests, zero failures and no skips** on the development Apple Silicon Mac. This includes the retained-source pathname-replacement regression. A 132-file FAT32 fixture copy/read-back took 0.93 seconds; physical USB speed and target-PC boot remain unverified. The release bundle also passes strict deep code-signature verification with ad-hoc signing.
