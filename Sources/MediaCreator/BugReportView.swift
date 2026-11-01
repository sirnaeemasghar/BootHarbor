// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    let operationLog: [String]
    @State private var copied = false
    private var diagnostics: String {
        "\(AppIdentity.name) \(AppIdentity.version)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n\nWhat happened:\n\nExpected result:\n\nOperation log (review personal paths before posting):\n" + operationLog.joined(separator: "\n")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Report a bug", systemImage: "ladybug").font(.title2.bold())
            Text("Help make this tool better. Include what happened, your Mac and macOS version, and the operation log.").foregroundStyle(.secondary)
            Text("Diagnostics are copied only when you choose. Review personal filenames before sharing them.").font(.callout)
            HStack {
                Button(copied ? "Report copied" : "Copy bug report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics, forType: .string)
                    copied = true
                }.buttonStyle(.borderedProminent)
                Link("Open issue tracker", destination: AppIdentity.issuesURL)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 550)
    }
}
