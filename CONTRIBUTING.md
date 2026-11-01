# Contributing

BootHarbor is an open-source community project. Contributions are welcome, especially reproducible compatibility reports and improvements to the device-safety and media pipelines.

## Build

Use a Mac with macOS 14+ and Xcode/Swift 6+. From the source directory:

```sh
./scripts/check-source.sh
./scripts/build-dependencies.sh
./scripts/swift-local.sh test
./scripts/package-app.sh
```

The dependency source archives and their checksums are committed. Build outputs,
expanded dependencies and local tool caches stay under Build/ and .local/.
Set DEVELOPER_DIR if your Xcode is not /Applications/Xcode.app.

For the integration suite, run `./scripts/test-integration.sh`. It creates its own
small disk-image device, checks its identity, and destroys only that fixture.
It does not enable virtual disks in the production writer. Never replace its
fixture with a physical disk identifier.

## Changes and verification

Describe the user-visible problem, resulting behavior and relevant checks.
Changes affecting writes, partitioning, device identity, privileges or cancellation
need meaningful regression coverage. Test destructive hardware scenarios only on
backed-up sacrificial media with explicit device selection.

A verified byte/file copy is distinct from a successful PC boot and completed
installation. Include the image SHA-256, architecture, firmware mode and target
hardware when reporting actual boot compatibility. Do not claim 5–10 minute
performance from a virtual-disk test.

Do not commit installation ISOs, WIM/ESD payloads, local hardware logs, signing
keys, credentials, .local/ or build products. Keep dependency notices and
corresponding source available. Project contributions are GPL-3.0-or-later.

## Security reports

Read SECURITY.md before reporting a potential unsafe-device or privilege-boundary
issue. Ordinary UI/build issues can use the public bug-report template.
