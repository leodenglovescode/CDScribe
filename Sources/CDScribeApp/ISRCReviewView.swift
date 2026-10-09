// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import CDScribeCore

struct ISRCBulkMenu: View {
    @Bindable var model: AppModel
    var body: some View {
        Menu("Choose ISRCs…") {
            let common = ISRCReview.commonCodes(model.album)
            if !common.isEmpty {
                Section("Shared choices for tracks with multiple values") {
                    ForEach(common, id: \.self) { code in
                        Button("Use \(code)") { model.applyISRCChoice(.suppliedCode(code)) }
                    }
                }
            }
            Section("Use each track’s own tagged value") {
                ForEach(ISRCReview.availablePositions(model.album), id: \.self) { position in
                    Button("Use tagged value \(position + 1) on all eligible tracks") { model.applyISRCChoice(.taggedValue(position)) }
                }
            }
            Divider()
            Button("Omit ISRC on all tracks") { model.applyISRCChoice(.omitAll) }
            Button("Reset all ISRC choices") { model.applyISRCChoice(.resetAll) }
        }.disabled(!model.hasAlbum || model.busy)
    }
}

struct ISRCReviewView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ISRC Preview & Check").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Review the code that will be written for each track. Checks run locally and cover format, multiple values, and repeated codes. Registration and recording matches are unchecked.").foregroundStyle(.secondary)
            HStack {
                ISRCBulkMenu(model: model)
                Spacer()
                Link("Open IFPI’s ISRC search", destination: URL(string: "https://isrc.ifpi.org/search")!)
                    .help("Opens an optional external website. CDScribe does not upload your tags or audio, or choose a recording for you.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let warnings = ISRCReview.warnings(model.album)
                    if !warnings.isEmpty {
                        GroupBox("Repeated codes · review recording identity") {
                            Text(warnings.joined(separator: "\n\n")).foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                    ForEach(ISRCReview.rows(model.album)) { row in
                        GroupBox("Track \(row.number) · \(row.title)") {
                            Grid(alignment: .leading, verticalSpacing: 8) {
                                GridRow { Text("Source tag").foregroundStyle(.secondary); Text(row.source.isEmpty ? "None" : row.source).monospaced() }
                                GridRow { Text("On disc").foregroundStyle(.secondary); Text(row.output.isEmpty ? "No ISRC will be written" : row.output).monospaced().bold() }
                                GridRow { Text("Check").foregroundStyle(.secondary); Text(row.status) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            if !row.malformedSourceValues.isEmpty {
                                Text("Malformed source values: " + row.malformedSourceValues.joined(separator: "; ")).foregroundStyle(.orange)
                            }
                            if let problem = row.problem { Text(problem).foregroundStyle(.orange) }
                        }
                    }
                }.textSelection(.enabled)
            }
            Text("ISRC is optional. Omitting it preserves audio playback and title/artist CD-Text. Every choice affects this disc only; source files remain unchanged.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 780, height: 680)
    }
}
