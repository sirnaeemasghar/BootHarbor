# Physical Windows USB test — 2026-11-01

The authorized Windows 10 USB run completed file copying and hash verification for all 907 prepared files (6,096,318,782 bytes). The source ISO was Win10_22H2_English_x64v1.iso, SHA-256 `a6f470ca6d331eb353b815c043e327a347f594f37ff525f17764738fe812852e`. Target: external UDisk, 15,728,640,000 bytes, FAT32/MBR. Large installation WIM was split into two verified SWM parts. Six boot files also passed an independent source-hash check.

The final safe-ejection command failed because macOS Spotlight (`mds_stores`) dissented to unmounting. The app displayed “Creation failed” for this final ejection-only error, despite its preceding “Files verified” log entry. No checksum failure was reported. Do not reformat or recreate the USB to resolve this error. Leave it connected until normal Finder ejection succeeds.

The existing app window and operation log were inspected read-only after its temporary job directory disappeared. No USB writes, format, force-unmount, process termination or retry was performed by the monitor. Background monitoring was stopped after recording the terminal result.

No target-PC boot or Windows installation test has been performed. Performance was slow, particularly the small-file copy/flush phase. Follow-up implementation work should distinguish verified-media/ejection-warning from failed creation and improve flushing/progress behavior.

Evidence: `Build/HardwareTest/result.json`, `expected-files.json`, `independent-boot-file-checks.json`, `heartbeat-progress.jsonl` and the existing app operation log.

Version 0.3 follow-up: verified media is now preserved as success with an ejection warning, with bounded normal-eject retries and a separate Eject USB action. Copying is buffered before per-file synchronization/read-back; device sessions are reused and idle sleep is prevented with scoped IOPM assertions. All 29 integration tests passed. The update did not rewrite this physical USB, so improved physical-drive timings remain unmeasured.
