# Architecture

`MediaCreator` is a SwiftUI application, `MediaCore` contains the image/device/file pipelines, and `MediaWriter` is a short-lived privileged executable bundled under `Contents/Helpers`.

## Device discovery and protection

Disk discovery uses `diskutil list -plist external physical` and individual `info -plist` calls. Actual macOS `WholeDisk` and `WritableMedia` keys are supported; older fixture keys are fallback only. Missing security fields fail closed. Eligible destinations must be writable, external, whole USB disks with valid disk identifiers and nonzero capacity.

The IOKit registry entry ID binds the confirmation to the current IOMedia instance. The helper rechecks registry ID, size, name and eligibility before formatting/opening. Raw writing claims the disk through Disk Arbitration, unmounts all its volumes, opens the raw character device, verifies its device number and revalidates identity again. The open descriptor is retained through writing and read-back, so a reused disk index is not reopened during copying.

Protected filesystem URLs resolve through APFS physical stores and disk-image backing files, with bounded ancestry recursion. The source image, app/helper, temporary workspace, and startup disk are excluded from the destination. Both the coordinator and helper perform protection checks.

## Image detection

Windows UEFI candidates require setup.exe, sources/boot.wim, an installation payload and a known EFI fallback filename. Structural recognition does not authenticate those files or prove firmware bootability. FAT32 files over 4,294,967,295 bytes require transformation; only install.wim/install.esd are automatically handled. Unknown oversized files are rejected.

Raw candidates require a sector-aligned image and supported MBR partition entries within source bounds. Protective-MBR images additionally require valid GPT header and partition-table CRCs and bounded entries. These checks are not an exhaustive filesystem/bootloader audit; firmware support follows the original image.

## Windows pipeline

Mount ISO read-only → inspect/enumerate paths → prepare large WIM/ESD parts in the temporary workspace → verify split parts → hash every file and budget cluster allocation plus overhead → hash the ISO → save a confirmed job → authenticate helper → freshly revalidate/protect → format MBR/FAT32 → drop helper privileges → buffered copy as the user → synchronize each file before its read-back → verify destination hashes → detach source → eject target.

wimlib first attempts splitting directly. If a compressed/solid payload cannot be split, it is exported to a normal LZX WIM and retried. Splitting/conversion happen before erasure. The part-size setting is 3800 MiB; a resource can cause a larger part, so every resulting file is checked against FAT32's actual limit. Split-set verification precedes destructive actions.

Copying refuses unexpected existing files, symlinks, special files, conflicting FAT32 names and unsupported paths. Target directories are opened component-by-component with `openat`/`O_NOFOLLOW`; file creation uses `O_EXCL`. The destination mount identity and USB registry entry are checked during copying. The preparation manifest's source file hashes are checked during copying and on destination read-back. Version 0.3 permits the OS to coalesce FAT/directory updates by copying all files before the flush/read-back pass. No flush or hash verification is omitted: fsync is required for each output file before its read-back checksum. Copy buffers are 4 MiB; large-file progress updates are limited to roughly five per second, plus file completion. A single Disk Arbitration session is reused for live identity checks; the current disk/media is still looked up on every check.

Windows output is UEFI installation media. No Windows legacy BIOS boot records are installed. MBR partitioning does not itself imply BIOS compatibility.

## Raw pipeline

Inspect partition structures → capacity/protected-volume checks → source identity and SHA-256 → authenticate helper → fresh safety checks → claim and unmount → open raw descriptor → drop user/group privileges permanently → copy in chunks with cancellation → fsync → read back exactly the source length and compare SHA-256 → close/release claim → eject.

Raw writing overwrites the image-length prefix, including the image's own partition/filesystem structures; it does not separately format FAT32. Remaining space follows the source image's partition layout and is not expanded automatically.

## Authorization and command execution

The app invokes its bundled helper using macOS administrator authorization via `osascript`'s `do shell script ... with administrator privileges`. Each shell argument is independently quoted, passed as argument data, and never inserted into AppleScript source. No passwords are collected by the app. This is a one-shot authorization path, not an installed SMAppService daemon.

The job is owner-only, size-bounded JSON. The helper reads it through an `O_NOFOLLOW` descriptor and compares its SHA-256 with the confirmed hash passed by the app. It checks ownership, operation enum, explicit erase acknowledgement and source metadata/checksum. The source is opened with the initiating user's effective access rights, and raw copying uses that retained source descriptor. The helper is limited to formatting an eligible USB or writing a validated image to an eligible USB; it does not accept arbitrary executable arguments.

Commands otherwise use fixed absolute executable paths and argument arrays. Secure temporary command logs are created with `O_EXCL|O_NOFOLLOW`, mode 0600; output is read back from the same descriptor. WIM subprocesses are terminated on cancellation. Formatting is a critical section: cancellation is honored before formatting and again afterward rather than killing diskutil midway.

No helper progress files are written as root. Root is dropped before raw output/progress and before post-format disk inspection. Windows file preparation/copy never runs as root.

## Remaining validation

The Windows administrator/helper/copy path was exercised on a physical USB with the supplied Windows 10 ISO; all file hashes passed. Actual PC boots, Secure Boot, other real installer images, host Intel/macOS 14 runtime and hot-unplug behavior still need hardware testing. The optimized 0.3 path needs a separate real-USB timing run. The virtual integration harness invokes the same disk-format command, claim/unmount implementation, copier and verifier on a disposable disk image without adding a production virtual-disk bypass. Ad-hoc signing is for local development; distribution signing/notarization and further security review are pending.

## Completion and sleep lifecycle (0.3)

An IOPM PreventUserIdleSystemSleep assertion spans the creation operation. The short-lived helper holds its own assertion too. Scoped cleanup releases assertions on success and errors; macOS releases them on process exit. This does not override explicit lid/manual/low-battery sleep or permanently change power settings.

After verification succeeds, source-image detachment and USB ejection are independently attempted. Transient busy/dissent responses receive at most three normal ejection attempts, each with a fresh target validation. No force-unmount, Spotlight termination or global indexing setting change is used. If ejection remains blocked, the result remains verified media with a safe-ejection warning. The Eject USB action is separate from media creation and cannot format or copy files.
