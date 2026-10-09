// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Diagnostics").font(.title2.bold()); Spacer()
                Button("Refresh") { model.refreshDiagnostics(scanBus: true) }.disabled(model.busy)
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
            LabeledContent("Writing engine", value: "cdrdao")
            Text("cdrdao uses the selected writer and checks blank media, CD-Text support, capacity and reported speeds before burning. Apple’s APIs provide drive discovery and CD-Text readback. Audio readback verification is currently unavailable.").font(.caption).foregroundStyle(.secondary)
            Section("Advanced: executable overrides") {
                TextField("FFmpeg", text: $model.ffmpegPath, prompt: Text("Included with CDScribe"))
                TextField("FFprobe", text: $model.ffprobePath, prompt: Text("Included with CDScribe"))
                TextField("cdrdao", text: $model.cdrdaoPath, prompt: Text("Included with CDScribe"))
                Text("FFmpeg, FFprobe and cdrdao are included. Leave these fields empty to use the bundled tools. Importing and burning work completely offline.").font(.caption).foregroundStyle(.secondary)
                Button("Apply") { model.saveSettings() }
            }
        }.formStyle(.grouped).padding(8).disabled(model.busy)
    }
}
