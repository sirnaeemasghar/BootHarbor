// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Used only after media copying and verification have succeeded.
public struct MediaFinalization: Sendable {
    public let sourceDetachWarning: String?
    public let ejectionWarning: String?
    public var ejected: Bool { ejectionWarning == nil }

    public static func finish(detachSource: () throws -> Void, eject: () throws -> Void,
                              retryDelay: () -> Void = { Thread.sleep(forTimeInterval: 1) }) -> MediaFinalization {
        var sourceWarning: String?
        var ejectWarning: String?
        do { try detachSource() } catch { sourceWarning = error.localizedDescription }
        // A source-image cleanup problem must not skip safe USB ejection.
        for attempt in 0..<3 {
            do { try eject(); ejectWarning = nil; break }
            catch {
                ejectWarning = error.localizedDescription
                let message = error.localizedDescription.lowercased()
                let busy = message.contains("dissented") || message.contains("busy") || message.contains("could not be unmounted")
                guard busy, attempt < 2 else { break }
                retryDelay()
            }
        }
        return MediaFinalization(sourceDetachWarning: sourceWarning, ejectionWarning: ejectWarning)
    }

    public func message(windows: Bool) -> String {
        var text = windows
            ? "Windows installation USB created and files verified."
            : "Image written and read-back SHA-256 verified."
        if let ejectionWarning {
            text += " Safe ejection was blocked: " + ejectionWarning
            text += " Keep the USB connected and eject it in Finder before unplugging. The verified media does not need to be recreated."
        } else {
            text += " USB safely ejected."
            if windows { text += " Boot the target PC in UEFI mode." }
        }
        if let sourceDetachWarning { text += " Source image cleanup warning: " + sourceDetachWarning }
        return text
    }
}
