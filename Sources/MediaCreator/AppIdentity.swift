// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

@MainActor
enum AppIdentity {
    static let author = "Naeem Asghar"
    static let githubProfile = URL(string: "https://github.com/sirnaeemasghar")!
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "BootHarbor" }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.1" }
    static let repositoryURL = URL(string: "https://github.com/sirnaeemasghar/BootHarbor")!
    static var issuesURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ProjectRepositoryURL") as? String,
           let url = URL(string: raw), url.scheme == "https", url.host == "github.com" {
            return url.appendingPathComponent("issues/new/choose")
        }
        return repositoryURL.appendingPathComponent("issues/new/choose")
    }
}

struct AppSymbol: View {
    private var icon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "BootHarbor") ?? NSImage(size: NSSize(width: 64, height: 64))
    }
    var body: some View {
        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            .accessibilityLabel("BootHarbor — Naeem Asghar portrait icon")
    }
}

struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            view.window?.isOpaque = false
            view.window?.backgroundColor = .clear
            view.window?.titlebarAppearsTransparent = true
        }
    }
}

struct GlassPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 20).fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    #if compiler(>=6.2)
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 20).fill(.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
                    }
                    #else
                    RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
                    #endif
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.07), lineWidth: 1))
    }
}
