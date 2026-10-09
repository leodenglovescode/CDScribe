// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Diagnostics").font(.title2.bold()); Spacer()
                Button("Refresh") { model.refreshDiagnostics() }.disabled(model.busy)
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.diagnostics + "\n\n" + model.logs.joined(separator: "\n"), forType: .string) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.diagnostics)
                    Divider()
                    Text(model.logs.joined(separator: "\n"))
                }.font(.system(.callout, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }.padding(24).frame(width: 820, height: 620)
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "System"
    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }
            Picker("Burning backend", selection: $model.backend) { Text("Apple DiscRecording").tag("DiscRecording"); Text("cdrdao (experimental on macOS)").tag("cdrdao") }
            Text("DiscRecording is the default. cdrdao must confirm device access and CD-Text support before writing.").font(.caption).foregroundStyle(.secondary)
            Section("Optional executable paths") {
                TextField("FFmpeg", text: $model.ffmpegPath, prompt: Text("Automatic detection"))
                TextField("FFprobe", text: $model.ffprobePath, prompt: Text("Automatic detection"))
                TextField("cdrdao", text: $model.cdrdaoPath, prompt: Text("Automatic detection"))
                Text("Normal importing and burning are completely offline. FFmpeg/FFprobe are required; cdrdao is optional.").font(.caption).foregroundStyle(.secondary)
                Button("Apply") { model.saveSettings() }
            }
        }.formStyle(.grouped).padding(8).disabled(model.busy)
    }
}
