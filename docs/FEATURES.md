# Feature matrix

| Feature | Current implementation | Validation |
| --- | --- | --- |
| Native Apple Silicon UI | Implemented | Builds; app UI inspected |
| USB discovery and hot-plug refresh | Implemented; corrected real macOS keys | Metadata regression tests; approximately 16 GB physical USB detected in the final UI |
| Erase confirmation | Exact drive identifier must be typed | UI implemented; no physical erasure executed |
| Windows 8/8.1/10/11 UEFI | Common installer layout pipeline | Windows 10 x64 physical USB files verified; each OS/architecture still needs PC boot tests |
| FAT32/MBR formatting | Implemented | Disposable virtual disk and real 16 GB USB formatted successfully |
| Large WIM/ESD | Split; export/retry for solid images | Real WIM split/verify/apply round trip; large real ISOs pending |
| Linux/raw image writing | MBR/GPT structural checks; raw copy | Disposable raw device copy and read-back SHA-256 pass |
| Source/app/startup exclusion | APFS/backing-image ancestry protection | Actual host/virtual-image ancestry tests pass |
| Device identity | IOKit registry instance plus fresh disk metadata | Nonzero/stable virtual identity across format verified |
| Exclusive raw access | Disk Arbitration claim and unmount | Disposable virtual device test passes |
| Verification | Windows file hashes; raw read-back SHA-256 | Automated round trips pass |
| Progress/cancel/logs/eject | Implemented | Cancellation and progress tests; physical interruption testing pending |
| Image SHA-256 | Streaming implementation | Known vector passes |
| Legacy BIOS Windows boot code | Not implemented | Separate bootloader work required |
| NTFS/UEFI:NTFS | Not implemented | Separate loader/licensing/Secure Boot work required |
| Secure Boot | Preserves source EFI files; not certified | Actual firmware tests required |
| Linux persistence / Windows To Go / FreeDOS | Not implemented | Separate pipelines |
| ISO downloads / Windows customization / hardware bypasses | Not implemented | Separate features |
| Compressed images / backups / bad-block tests | Not implemented | Separate formats/features |
| Intel host support | Swift target is portable; not built/tested here | Intel dependency build and host run required |
| Public release | Version 0.3 local ad-hoc-signed build only | Hardware testing, security review, signing/notarization pending |

Full Rufus parity remains a long-term goal. Current functionality targets the original Windows installer and common Linux hybrid-image use cases; no claim of support for every ISO or every computer is made.

Version 0.3 also adds scoped idle-sleep assertions, buffered/deferred flush/read-back, reused device sessions, bounded normal ejection retries and a separate Eject USB action. A blocked eject is reported as a warning after successful verification. These changes passed 29 integration tests; no new physical USB write was performed for this update.
