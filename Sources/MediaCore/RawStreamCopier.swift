// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit
import Darwin

public enum RawStreamCopier {
    public static func copyAndVerify(source: FileHandle, destination: FileHandle, size: UInt64,
                                     expectedSHA256: String, control: WriteControl) throws {
        guard size > 0, size % 512 == 0 else { throw MediaError.unsupportedImage }
        try source.seek(toOffset: 0)
        try destination.seek(toOffset: 0)
        var written: UInt64 = 0
        var sourceHash = SHA256()
        while written < size {
            try control.check()
            let requested = Int(min(4 * 1024 * 1024, size - written))
            guard let bytes = try source.read(upToCount: requested), bytes.count == requested else {
                throw MediaError.commandFailed("The source image changed or could not be read completely.")
            }
            sourceHash.update(data: bytes)
            try destination.write(contentsOf: bytes)
            written += UInt64(bytes.count)
            control.report(WriteProgress("Writing image", completed: written, total: size))
        }
        guard digest(sourceHash) == expectedSHA256 else { throw MediaError.commandFailed("Source checksum changed during writing. USB creation failed.") }
        guard fsync(destination.fileDescriptor) == 0 else { throw MediaError.commandFailed("Could not flush the USB writes: " + String(cString: strerror(errno))) }
        try destination.seek(toOffset: 0)
        var readBack: UInt64 = 0
        var destinationHash = SHA256()
        while readBack < size {
            try control.check()
            let requested = Int(min(4 * 1024 * 1024, size - readBack))
            guard let bytes = try destination.read(upToCount: requested), bytes.count == requested else {
                throw MediaError.commandFailed("USB read-back was incomplete.")
            }
            destinationHash.update(data: bytes)
            readBack += UInt64(bytes.count)
            control.report(WriteProgress("Verifying USB", completed: readBack, total: size))
        }
        guard digest(destinationHash) == expectedSHA256 else { throw MediaError.commandFailed("USB read-back checksum did not match the source.") }
    }
    private static func digest(_ hash: SHA256) -> String {
        hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
