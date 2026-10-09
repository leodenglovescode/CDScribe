// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit
import CDScribeCore

struct MainView: View {
    @Bindable var model: AppModel
    @State private var targeted = false
    @State private var reviewedTrackID: UUID?
    @AppStorage("appearance") private var appearance = "System"
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                artwork
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("CDScribe").font(.title2.weight(.semibold))
                        Spacer()
                        Text("AUDIO CD · CD-TEXT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if model.hasAlbum {
                        TextField("Album title", text: $model.album.title).font(.title.bold()).textFieldStyle(.plain).accessibilityLabel("Album title")
                        TextField("Album artist", text: $model.album.artist).font(.title3).textFieldStyle(.plain).accessibilityLabel("Album artist")
                        HStack(spacing: 12) {
                            Label("\(model.album.tracks.count) tracks", systemImage: "music.note.list")
                            Text(CDDA.time(model.album.duration)).monospacedDigit()
                            Text("Disc \(model.album.discNumber)")
                        }.font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Your music, written right.").font(.largeTitle.weight(.semibold))
                        Text("Drag in a FLAC album. Its tags become the text on your CD.").foregroundStyle(.secondary)
                    }
                    if model.albums.count > 1 {
                        Picker("Album / disc", selection: $model.selectedIndex) {
                            ForEach(model.albums.indices, id: \.self) { i in
                                Text("\(model.albums[i].title) · Disc \(model.albums[i].discNumber)").tag(i)
                            }
                        }.pickerStyle(.menu)
                    }
                }
            }.padding(24).disabled(model.busy)
            Divider()
            if model.hasAlbum { trackTable }
            else { emptyState }
            Divider()
            burnPanel
            Divider()
            statusBar
        }
        .background(.background)
        .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
        .overlay {
            if targeted { RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3).padding(5).allowsHitTesting(false) }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !model.busy else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                            continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
                        }
                    }
                    if let url { urls.append(url) }
                }
                if !urls.isEmpty { model.importURLs(urls) }
            }
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.openFiles() } label: { Label("Open FLAC Files", systemImage: "folder") }.disabled(model.busy)
                Button { model.showPreview = true } label: { Label("CD-Text Preview", systemImage: "text.alignleft") }.disabled(!model.hasAlbum)
                Button { model.showDiagnostics = true } label: { Label("Diagnostics", systemImage: "stethoscope") }
            }
        }
        .sheet(isPresented: $model.showPreview) { CDTextPreviewView(model: model) }
        .sheet(isPresented: $model.showISRCReview) { ISRCReviewView(model: model) }
        .sheet(isPresented: $model.showDiagnostics) { DiagnosticsView(model: model) }
        .alert("CDScribe stopped", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        .alert("Burn finished", isPresented: Binding(get: { model.resultMessage != nil }, set: { if !$0 { model.resultMessage = nil } })) { Button("OK") { model.resultMessage = nil } } message: { Text(model.resultMessage ?? "") }
        .confirmationDialog("Abort the physical burn?", isPresented: $model.showCancelWarning, titleVisibility: .visible) {
            Button("Abort Burn", role: .destructive) { model.confirmCancel() }
        } message: { Text("Aborting may make this CD-R unusable. CDScribe will wait for the drive to stop before releasing the prepared audio.") }
        .task {
            if CommandLine.arguments.contains("--smoke-test") { await model.runSmokeTestIfRequested() }
            model.refreshDiagnostics()
            while !Task.isCancelled {
                do { try await model.refreshDrives(); try await Task.sleep(for: .seconds(3)) }
                catch is CancellationError { break }
                catch { model.log(error.localizedDescription); try? await Task.sleep(for: .seconds(3)) }
            }
        }
        .onOpenURL { url in if !model.busy { model.importURLs([url]) } }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let data = model.album.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "opticaldisc").font(.system(size: 65, weight: .ultraLight)).foregroundStyle(.secondary)
            }
        }.frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Album artwork. Artwork is displayed here and is not written into CD-Text.")
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.and.arrow.down").font(.system(size: 40, weight: .light)).foregroundStyle(.tint)
            Text("Drop your album here").font(.title2.weight(.medium))
            Text("FLAC files or an album folder\nTitles, artists, track order and artwork are read locally.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                Button("Open FLAC Files…") { model.openFiles() }.keyboardShortcut("o")
                Button("Open Folder…") { model.openFiles(folder: true) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
    private var trackTable: some View {
        VStack(spacing: 0) {
            Table($model.album.tracks, selection: $model.selection) {
                TableColumn("#") { $track in
                    Text("\((model.album.tracks.firstIndex(where: { $0.id == track.id }) ?? 0) + 1)").monospacedDigit()
                }.width(30)
                TableColumn("Title") { $track in TextField("Title", text: $track.title).textFieldStyle(.plain) }.width(min: 190, ideal: 280)
                TableColumn("Artist") { $track in TextField("Artist", text: $track.artist).textFieldStyle(.plain) }.width(min: 130, ideal: 200)
                TableColumn("Duration") { $track in Text(CDDA.time(track.duration)).monospacedDigit() }.width(65)
                TableColumn("ISRC") { $track in
                    if MetadataMapper.isrcValues(track.isrc).count > 1 {
                        Menu {
                            Button("Omit ISRC (optional)") { track.isrcSelection = "" }
                            ForEach(track.isrcCandidates, id: \.self) { code in
                                Button(code) { track.isrcSelection = code }
                            }
                        } label: {
                            Text(track.isrcSelection.flatMap { $0.isEmpty ? nil : $0 } ?? "Multiple · omitted")
                                .font(.system(.caption, design: .monospaced))
                        }.help("Source ISRC values: \(track.isrc). A CD track accepts one code. Choose a supplied code or omit this optional field.")
                    } else {
                        TextField("Optional", text: $track.isrc).textFieldStyle(.plain).font(.system(.caption, design: .monospaced))
                    }
                }.width(140)
                TableColumn("Metadata") { $track in
                    if track.metadataWarnings.isEmpty {
                        Label("Tagged", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    } else {
                        Button { reviewedTrackID = track.id } label: {
                            Label("Review", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }.buttonStyle(.plain)
                        .help(track.metadataWarnings.joined(separator: "\n"))
                        .popover(isPresented: Binding(get: { reviewedTrackID == track.id }, set: { if !$0 { reviewedTrackID = nil } })) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(track.title).font(.headline)
                                Text(track.metadataWarnings.joined(separator: "\n\n"))
                                if !track.isrc.isEmpty { Text("Source ISRC: \(track.isrc)").font(.caption).textSelection(.enabled) }
                            }.padding(18).frame(width: 360)
                        }
                    }
                }.width(85)
            }.disabled(model.busy)
            HStack {
                Button { model.moveTrack(-1) } label: { Image(systemName: "arrow.up") }.help("Move selected track up").accessibilityLabel("Move selected track up")
                Button { model.moveTrack(1) } label: { Image(systemName: "arrow.down") }.help("Move selected track down").accessibilityLabel("Move selected track down")
                Text("Edits affect this disc only; your FLAC files stay untouched.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ISRCBulkMenu(model: model)
                Button("ISRC Preview…") { model.showISRCReview = true }
                Button("CD-Text Preview…") { model.showPreview = true }
            }.padding(10).disabled(model.busy)
            if let warning = ISRCReview.warnings(model.album).first {
                Button { model.showISRCReview = true } label: {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 8)
            }
            if let warning = model.album.warnings.first {
                Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }
    private var burnPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Writer", selection: $model.driveID) {
                        Text(model.drives.isEmpty ? "No CD writer detected" : "Choose writer").tag("")
                        ForEach(model.drives) { drive in Text(drive.name).tag(drive.id) }
                    }.frame(maxWidth: 390)
                    if let drive = model.selectedDrive {
                        Label("\(drive.mediaType) · \(drive.blank ? "Blank" : "Not blank") · \(drive.capacity > 0 ? CDDA.time(Double(drive.capacity) / 75) : "Capacity unavailable")", systemImage: "opticaldisc").font(.caption).foregroundStyle(.secondary)
                        if !drive.cdText || !drive.sao { Text("This writer does not advertise the required CD-Text writing mode.").font(.caption).foregroundStyle(.orange) }
                    } else { Text("Connect a USB CD writer and insert a blank CD-R.").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button("Refresh") { Task { try? await model.refreshDrives() } }
                        Button("Read CD-Text") { model.readCDText() }.disabled(model.selectedDrive?.present != true || model.busy)
                    }.controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Speed", selection: $model.speed) {
                            if model.availableSpeeds.isEmpty { Text("Unavailable").tag(Double(0)) }
                            ForEach(model.availableSpeeds, id: \.self) { speed in Text(BurnSpeedPolicy.label(speed)).tag(speed) }
                        }.frame(width: 180).disabled(model.availableSpeeds.isEmpty)
                        Picker("Capacity", selection: $model.capacityMinutes) { Text("74 min").tag(74); Text("80 min").tag(80) }.frame(width: 170)
                    }
                    if model.availableSpeeds.isEmpty {
                        Text(model.speedUnavailableReason)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Picker("Track pause", selection: $model.gapSeconds) { Text("Gapless").tag(0); ForEach(1...10, id: \.self) { Text("\($0) sec").tag($0) } }.frame(width: 180)
                        Toggle("Verify after burning", isOn: $model.verify)
                    }
                }
                Spacer(minLength: 0)
            }.disabled(model.busy)
            if model.backend == "cdrdao" {
                HStack {
                    Text("Experimental cdrdao device:")
                    TextField("Exact identifier from scanbus", text: $model.cdrdaoDevice)
                }.font(.caption).disabled(model.busy)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    let mediaCapacity = model.selectedDrive?.capacity ?? 0
                    let cap = mediaCapacity > 0 ? mediaCapacity : model.planningCapacity
                    let fraction = Double(model.estimatedLayout.totalSectors) / Double(max(1, min(cap, model.planningCapacity)))
                    HStack {
                        Text(model.hasAlbum ? "\(CDDA.time(model.estimatedLayout.duration)) incl. pregaps" : "No audio imported")
                        Spacer()
                        Text("\(model.capacityMinutes)-minute CD")
                    }.font(.caption).foregroundStyle(fraction > 1 ? Color.red : .secondary)
                    ProgressView(value: min(1, fraction)).tint(fraction > 1 ? .red : .accentColor)
                }.frame(maxWidth: .infinity)
                Button { model.burn() } label: { Label("Burn Audio CD", systemImage: "flame") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canBurn)
                    .help("Automatically converts FLAC to standard CD audio, validates the layout, then writes the disc with CD-Text.")
                    .accessibilityHint("Converts your audio automatically before burning.")
            }
            Text("FLACs convert automatically when you click Burn Audio CD.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18)
    }
    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.busy {
                if let fraction = model.progress.fraction { ProgressView(value: fraction).frame(width: 100) }
                else { ProgressView().controlSize(.small) }
            } else { Image(systemName: model.prepared == nil ? "info.circle" : "checkmark.circle").foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.progress.stage).font(.caption.weight(.semibold))
                Text(model.progress.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if model.busy { Button(model.burning ? "Abort…" : "Cancel") { model.cancel() } }
            if model.prepared != nil && !model.busy { Button("Export Prepared Disc…") { model.exportPrepared() } }
        }.padding(.horizontal, 18).padding(.vertical, 10).frame(minHeight: 55)
    }
}
