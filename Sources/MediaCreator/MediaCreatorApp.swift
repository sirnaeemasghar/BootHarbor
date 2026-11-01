// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MediaCore

@main
struct MediaCreatorApp: App {
    var body: some Scene {
        WindowGroup { CreatorView() }
            .defaultSize(width: 840, height: 760)
            .windowStyle(.hiddenTitleBar)
    }
}

private struct EraseRequest: Identifiable {
    let id = UUID()
    let image: MediaImage
    let device: USBDevice
}

@MainActor
struct CreatorView: View {
    @State private var devices: [USBDevice] = []
    @State private var selection: String?
    @State private var image: MediaImage?
    @State private var status = "Choose an installation image and connect a USB drive."
    @State private var isLoading = false
    @State private var isWriting = false
    @State private var showImporter = false
    @State private var showBugReport = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var inspection: ImageInspection?
    @State private var checksum: String?
    @State private var progress: WriteProgress?
    @State private var control: WriteControl?
    @State private var eraseRequest: EraseRequest?
    @State private var eraseText = ""
    @State private var logs: [String] = []
    private var busy: Bool { isLoading || isWriting }

    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else {
                WindowGlass().ignoresSafeArea()
                LinearGradient(colors: [.cyan.opacity(0.10), .clear, .blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            }
            VStack(spacing: 22) {
                header
                ScrollView {
                    VStack(spacing: 16) {
                        imagePanel
                        devicePanel
                        activityPanel
                    }.padding(.horizontal, 2).padding(.bottom, 4)
                }.scrollIndicators(.hidden)
                footer
            }.padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 18)
        }
        .frame(minWidth: 760, minHeight: 690)
        .task {
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
                if !busy && eraseRequest == nil { await refresh(silent: true) }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            do {
                inspection = nil; checksum = nil
                let selected = try MediaImage(url: result.get()); image = selected
                Task { await inspectImage(selected) }
            } catch { image = nil; status = error.localizedDescription }
        }
        .sheet(item: $eraseRequest) { request in eraseReview(request) }
        .sheet(isPresented: $showBugReport) { BugReportView(operationLog: logs) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            if isWriting { try? control?.cancel() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppSymbol().frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.name).font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("Windows & Linux USB Creator").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Text("v" + AppIdentity.version).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { showBugReport = true } label: { Label("Report a bug", systemImage: "ladybug") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
    private var imagePanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("01").font(.caption.monospaced()).foregroundStyle(.tertiary)
                    Text("Installation image").font(.headline)
                    Spacer()
                    if let image { Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: image.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 12) {
                    Image(systemName: "opticaldisc").font(.system(size: 29, weight: .light)).foregroundStyle(.cyan)
                        .frame(width: 48, height: 48).background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(image?.url.lastPathComponent ?? "Choose your installation image").font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text(image == nil ? "Windows or Linux ISO · Raw disk IMG" : "Source image selected").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    Button(image == nil ? "Choose image…" : "Change…") { showImporter = true }.disabled(busy)
                }
                if let inspection {
                    HStack(spacing: 8) {
                        Image(systemName: inspection.strategy == .unsupported ? "info.circle" : "checkmark.circle").foregroundStyle(inspection.strategy == .unsupported ? .orange : .cyan)
                        Text(inspection.strategy == .rawCandidate ? "Direct image writing" : inspection.strategy.rawValue).font(.caption)
                        Spacer()
                        if let image {
                            Button("SHA-256") { Task { await hashImage(image) } }.disabled(busy)
                            Button("Inspect") { Task { await inspectImage(image) } }.disabled(busy)
                        }
                    }.controlSize(.small)
                }
                if let checksum { Text(checksum).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2) }
            }
        }
    }
    private var devicePanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("02").font(.caption.monospaced()).foregroundStyle(.tertiary)
                    Text("Destination USB").font(.headline)
                    Spacer()
                    Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .controlSize(.small).disabled(busy)
                }
                if devices.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive").font(.system(size: 27, weight: .light)).foregroundStyle(.secondary)
                            .frame(width: 48, height: 48).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect a USB drive").font(.callout.weight(.medium))
                            Text("External drives appear here automatically.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Picker("Drive", selection: $selection) {
                        Text("Select an external USB drive").tag(nil as String?)
                        ForEach(devices) { device in
                            Text("\(device.name) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: device.size), countStyle: .file)) · /dev/\(device.identifier)")
                                .tag(Optional(device.identifier))
                        }
                    }.disabled(busy)
                }
                Label("Creating installation media erases the selected USB. Back up its files first.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isWriting, let progress {
                if progress.total > 0 { ProgressView(value: progress.fraction).tint(.cyan) }
                else { ProgressView().controlSize(.small) }
                HStack {
                    Text(progress.phase).font(.callout).lineLimit(2)
                    Spacer()
                    if progress.total > 0 { Text("\(Int(progress.fraction * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
            }
            Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if !logs.isEmpty {
                DisclosureGroup("Operation log") {
                    ScrollView { Text(logs.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
                    Button("Copy log") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(logs.joined(separator: "\n"), forType: .string) }
                }.font(.caption)
            }
        }.padding(.horizontal, 4).padding(.top, 2)
    }
    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if isLoading { ProgressView().controlSize(.small) }
                Label("Verified writes. Idle sleep paused while working.", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                if isWriting {
                    Button("Cancel") {
                        do { try control?.cancel(); status = "Cancelling… USB may contain incomplete installation media." }
                        catch { status = error.localizedDescription }
                    }
                } else {
                    Button("Eject USB") { Task { await ejectSelection() } }.disabled(busy || selection == nil)
                    Button("Create installation USB…") { reviewErase() }.buttonStyle(.borderedProminent).tint(.cyan)
                        .disabled(busy || image == nil || selection == nil || inspection == nil || inspection?.strategy == .unsupported)
                }
            }
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
            HStack(spacing: 5) {
                Text("Built with love ❤️ by").foregroundStyle(.secondary)
                Link(AppIdentity.author, destination: AppIdentity.githubProfile)
                Text("·").foregroundStyle(.tertiary)
                Link("GitHub", destination: AppIdentity.githubProfile)
            }.font(.caption).tint(.primary.opacity(0.75))
        }
    }
    private func eraseReview(_ request: EraseRequest) -> some View {
        let device = request.device
        let image = request.image
        return VStack(alignment: .leading, spacing: 18) {
            Label("Erase USB and create installation media?", systemImage: "exclamationmark.triangle.fill").font(.title2.bold()).foregroundStyle(.orange)
            Text("Image: \(image.url.lastPathComponent)")
            Text("USB: \(device.name) · /dev/\(device.identifier) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: device.size), countStyle: .file))")
            Text("All partitions and files on this USB will be permanently erased. macOS will ask for administrator authorization after image preparation.")
            Text("Type \(device.identifier) to confirm this exact drive.").font(.callout.bold())
            TextField(device.identifier, text: $eraseText).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { eraseRequest = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Erase & Create", role: .destructive) {
                    eraseRequest = nil
                    Task { await create(image: image, device: device) }
                }.buttonStyle(.borderedProminent).tint(.red).disabled(eraseText != device.identifier)
            }
        }.padding(28).frame(width: 540)
    }
    private func reviewErase() {
        guard let selected = devices.first(where: { $0.identifier == selection }), let image else { return }
        eraseText = ""; eraseRequest = EraseRequest(image: image, device: selected)
    }
    private func create(image: MediaImage, device: USBDevice) async {
        isWriting = true; logs = []; status = "Preparing the image before erasing the USB."
        var directory: URL?
        defer {
            isWriting = false; control = nil
            if let directory { try? FileManager.default.removeItem(at: directory) }
        }
        do {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("media-job-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            directory = path
            let jobControl = WriteControl(directory: path); control = jobControl
            let app = Bundle.main.bundleURL
            let service = MediaCreation(helper: app.appendingPathComponent("Contents/Helpers/MediaWriter"),
                                        wimTool: app.appendingPathComponent("Contents/Helpers/wimlib-imagex"), application: app)
            let monitor = Task {
                var previous = ""
                while !Task.isCancelled {
                    if let latest = jobControl.readProgress() {
                        progress = latest
                        if latest.phase != previous {
                            previous = latest.phase
                            logs.append(Date().formatted(date: .omitted, time: .standard) + "  " + latest.phase)
                            if logs.count > 500 { logs.removeFirst() }
                        }
                    }
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                }
            }
            defer { monitor.cancel() }
            let result = try await Task.detached { try service.create(image: image, device: device, control: jobControl) }.value
            status = result; progress = WriteProgress("Complete", completed: 1, total: 1); logs.append(result)
        } catch {
            status = control?.isCancelled == true || error is CancellationError
                ? "Cancelled. The USB may be incomplete. Create the installation media again before using it."
                : "Creation failed: " + error.localizedDescription
            logs.append(status)
        }
    }
    private func ejectSelection() async {
        guard let device = devices.first(where: { $0.identifier == selection }) else { return }
        isLoading = true; status = "Safely ejecting USB…"
        let result = await Task.detached {
            MediaFinalization.finish(detachSource: {}, eject: {
                try DiskService().revalidate(device)
                _ = try CommandRunner().run("/usr/sbin/diskutil", ["eject", device.identifier])
            })
        }.value
        if result.ejected {
            status = "USB safely ejected. You can unplug it now."
            selection = nil
        } else {
            status = "Safe ejection is still blocked: " + (result.ejectionWarning ?? "Drive is busy.") + " Keep the USB connected; retry Eject USB when other apps have finished using it."
        }
        logs.append(status); isLoading = false
        await refresh(silent: true)
    }
    private func hashImage(_ selected: MediaImage) async {
        isLoading = true; status = "Calculating SHA-256…"
        do {
            let result = try await Task.detached { try ImageChecksum().sha256(of: selected.url) }.value
            if image?.url == selected.url { checksum = result; status = "Compare this SHA-256 with the image publisher’s checksum." }
        } catch { status = error.localizedDescription }
        isLoading = false
    }
    private func inspectImage(_ selected: MediaImage) async {
        isLoading = true; status = "Inspecting image…"
        do {
            let result = try await Task.detached { try ImageInspector().inspect(selected) }.value
            if image?.url == selected.url { inspection = result; status = result.notes }
        } catch { inspection = nil; status = error.localizedDescription }
        isLoading = false
    }
    private func refresh(silent: Bool = false) async {
        if !silent { isLoading = true }
        do {
            let found = try await Task.detached { try DiskService().devices() }.value
            devices = found
            if !found.contains(where: { $0.identifier == selection }) { selection = nil }
            if !silent { status = found.isEmpty ? "Connect a USB drive to continue." : "Select the USB drive to erase and use for installation media." }
        } catch {
            devices = []; selection = nil
            if !silent { status = error.localizedDescription }
        }
        if !silent { isLoading = false }
    }
}
