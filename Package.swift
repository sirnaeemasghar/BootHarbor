// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "BootHarbor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BootHarbor", targets: ["MediaCreator"])],
    targets: [
        .target(name: "MediaCore"),
        .executableTarget(name: "MediaWriter", dependencies: ["MediaCore"]),
        .executableTarget(name: "MediaCreator", dependencies: ["MediaCore"]),
        .testTarget(name: "MediaCoreTests", dependencies: ["MediaCore"])
    ]
)
