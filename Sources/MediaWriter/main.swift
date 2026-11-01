// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit
import Darwin
import MediaCore

func fail(_ error: Error) -> Never {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
func dropPrivileges(to uid: UInt32) throws {
    guard let entry = getpwuid(uid), uid != 0,
          setgroups(0, nil) == 0, setgid(entry.pointee.pw_gid) == 0, setuid(uid) == 0,
          geteuid() == uid else { throw MediaError.commandFailed("Cannot drop administrator privileges.") }
}
func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 3, geteuid() == 0 else {
        throw MediaError.commandFailed("MediaWriter must be launched by the app with a confirmed job and administrator authorization.")
    }
    let path = URL(fileURLWithPath: arguments[1])
    let fd = open(path.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw MediaError.invalidResponse }
    let manifestHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size < 1_048_576 else { throw MediaError.invalidResponse }
    let data = try manifestHandle.readToEnd() ?? Data()
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == arguments[2] else { throw MediaError.commandFailed("The confirmed write job was modified.") }
    let job = try JSONDecoder().decode(WriteJob.self, from: data)
    try job.validate()
    let activity = try SystemActivity()
    defer { activity.end() }
    guard info.st_uid == job.ownerUID, job.ownerUID != 0 else { throw MediaError.unsafeDevice }
    let control = WriteControl(directory: path.deletingLastPathComponent())
    try control.check()
    let service = DiskService()
    let imageURL = URL(fileURLWithPath: job.imagePath)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    try service.protect([imageURL, executable, path.deletingLastPathComponent()] + job.protectedPaths.map { URL(fileURLWithPath: $0) }, from: job.device)
    // Open the image with the initiating user's access rights, never root-only file access.
    guard seteuid(job.ownerUID) == 0 else { throw MediaError.unsafeDevice }
    let sourceFD = open(imageURL.path, O_RDONLY | O_NOFOLLOW)
    let sourceError = errno
    guard seteuid(0) == 0 else { throw MediaError.unsafeDevice }
    guard sourceFD >= 0 else { throw MediaError.commandFailed("Cannot open image: " + String(cString: strerror(sourceError))) }
    let source = FileHandle(fileDescriptor: sourceFD, closeOnDealloc: true)
    guard try SourceIdentity(fileDescriptor: sourceFD) == job.imageIdentity else { throw MediaError.commandFailed("The source image changed. Select it again.") }
    // Hash the same opened file descriptor that will be copied.
    var hash = SHA256()
    while let bytes = try source.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty {
        try control.check(); hash.update(data: bytes)
    }
    guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == job.sourceSHA256 else {
        throw MediaError.commandFailed("The source image checksum changed before writing.")
    }
    try control.check()
    try service.revalidate(job.device)
    switch job.operation {
    case .formatWindows:
        // The helper only formats a validated external USB; copying/WIM tools run as the user.
        _ = try CommandRunner().run("/usr/sbin/diskutil", ["eraseDisk", "MS-DOS FAT32", "WININSTALL", "MBRFormat", "/dev/" + job.device.identifier])
        try dropPrivileges(to: job.ownerUID)
        let volume = try service.mountedFAT32Partition(on: job.device)
        let result = try JSONEncoder().encode(["mountPoint": volume.path])
        FileHandle.standardOutput.write(result)
    case .raw:
        guard try RawImageProbe.supports(source, imageSize: UInt64(job.imageIdentity.size)) else { throw MediaError.unsupportedImage }
        let claim = try ExclusiveDisk(identifier: job.device.identifier)
        defer { withExtendedLifetime(claim) {} }
        try control.check()
        try service.revalidate(job.device)
        let node = "/dev/rdisk" + job.device.identifier.dropFirst(4)
        let destinationFD = open(node, O_RDWR | O_NOFOLLOW)
        guard destinationFD >= 0 else { throw MediaError.commandFailed("Cannot open USB for writing: " + String(cString: strerror(errno))) }
        let destination = FileHandle(fileDescriptor: destinationFD, closeOnDealloc: true)
        defer { try? destination.close() }
        var opened = stat(), named = stat()
        guard fstat(destinationFD, &opened) == 0, lstat(node, &named) == 0,
              opened.st_mode & S_IFMT == S_IFCHR, opened.st_rdev == named.st_rdev else { throw MediaError.unsafeDevice }
        try service.revalidate(job.device)
        try dropPrivileges(to: job.ownerUID)
        try RawStreamCopier.copyAndVerify(source: source, destination: destination,
                                         size: UInt64(job.imageIdentity.size), expectedSHA256: job.sourceSHA256, control: control)
        FileHandle.standardOutput.write(Data("{\"verified\":true}".utf8))
    }
}
do { try run() } catch { fail(error) }
