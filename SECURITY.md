# Security and data-safety status

This project is a development preview. It intentionally performs destructive USB
operations after explicit drive confirmation and macOS administrator authorization.
It has not received an independent security audit and is not a certified safe
replacement for all Rufus workflows.

## Reporting

Once the repository is published, use its **Security → Report a vulnerability**
channel if private vulnerability reporting has been enabled. The maintainer must
enable this before inviting private reports. No monitored security email address
has been established yet. Do not post credentials, private files or exploitable
privilege-escalation details in a public issue. Publicly visible, non-sensitive
safety problems may be reported through the normal issue template.

## Current boundary

The UI is unprivileged. A one-shot helper accepts a bounded, owner-only, hashed
job and validates the external whole USB, current IOKit identity, source identity
and checksum, and protected-volume ancestry. Raw writes claim/unmount the device
and retain an open device descriptor. Windows files are opened relative to an
already-open directory and refuse symlinks/unexpected existing files. WIM tools
and filesystem copying run as the normal user. Source metadata and destination
hashes are checked. Full verification is not optional.

These measures reduce risk but do not constitute proof against all races or
malicious local processes. Windows formatting still delegates to diskutil using a
freshly validated disk identifier; review of that hand-off and the ad-hoc-signed
helper trust model remains a stable-release gate. No permanent privileged daemon,
force-unmount, global Spotlight change or user power-preference change is installed.

## Before a stable binary release

- Independent review of the privileged helper and device replacement races.
- End-to-end PC boot/installation tests and unplug/cancel/error tests on backed-up media.
- Intel/macOS-version coverage and measured optimized physical-USB performance.
- Developer ID signing/notarization and a defined private reporting channel.

Do not run extra USB erasures merely to reproduce an ejection warning. If files
are verified and macOS blocks ejection, keep the drive connected and retry normal
ejection after the other process finishes.
