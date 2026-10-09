// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import CDScribeCore

struct CDTextPreviewView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("CD-Text Preview").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            Text("This is the text CDScribe will write to the disc. Edit album and track fields in the review table.").foregroundStyle(.secondary)
            Picker("Character encoding", selection: $model.policy) { ForEach(TextEncodingPolicy.allCases) { Text($0.rawValue).tag($0) } }.disabled(model.busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.textResult {
                    case .success(let text):
                        GroupBox("Disc") {
                            Grid(alignment: .leading) {
                                GridRow { Text("TITLE").foregroundStyle(.secondary); Text(text.title).bold() }
                                GridRow { Text("PERFORMER").foregroundStyle(.secondary); Text(text.performer) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                        ForEach(Array(text.tracks.enumerated()), id: \.offset) { index, track in
                            GroupBox("Track \(index + 1)") {
                                Grid(alignment: .leading) {
                                    GridRow { Text("TITLE").foregroundStyle(.secondary); Text(track.title) }
                                    GridRow { Text("PERFORMER").foregroundStyle(.secondary); Text(track.performer) }
                                    if !track.isrc.isEmpty { GridRow { Text("ISRC").foregroundStyle(.secondary); Text(track.isrc).monospaced() } }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            }
                        }
                        if !text.changes.isEmpty {
                            GroupBox("Review metadata and encoding changes") { Text(text.changes.joined(separator: "\n")).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.orange) }
                        }
                        if let error = nativeError(text) { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        if let toc = try? TOCGenerator.render(text: text, layout: model.estimatedLayout) {
                            DisclosureGroup("TOC layout") { Text(toc).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        }
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }.textSelection(.enabled)
            }
            Text("CD-Text carries titles and performers. It does not contain album artwork or control online album recognition in Music.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 720, height: 680)
    }
    private func nativeError(_ text: CDText) -> String? {
        do { _ = try NativeBurningService.validateText(text); return nil } catch { return error.localizedDescription }
    }
}
