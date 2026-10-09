// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import CDScribeCore

@MainActor @Observable
final class AppModel {
    var albums: [AlbumModel] = []
    var selectedIndex = 0 { didSet { invalidate() } }
    var selection: UUID?
    var drives: [DiscDrive] = []
    var driveID = "" { didSet { if oldValue != driveID { updateSpeedSelection() } } }
    var speed: Double = 0
    var gapSeconds = 0 { didSet { invalidate() } }
    var capacityMinutes = 80 { didSet { invalidate() } }
    var policy: TextEncodingPolicy = .latin1 { didSet { invalidate() } }
    var verify = true
    var backend = "DiscRecording" { didSet { updateSpeedSelection() } }
    var cdrdaoDevice = "" { didSet { updateSpeedSelection() } }
    var ffmpegPath = UserDefaults.standard.string(forKey: "ffmpegPath") ?? ""
    var ffprobePath = UserDefaults.standard.string(forKey: "ffprobePath") ?? ""
    var cdrdaoPath = UserDefaults.standard.string(forKey: "cdrdaoPath") ?? ""
    var busy = false
    var burning = false
    var progress = OperationProgress("Ready", "Drag an album folder or FLAC files to begin")
    var errorMessage: String?
    var resultMessage: String?
    var diagnostics = "Checking installed backends…"
    var logs: [String] = []
    var showPreview = false
    var showISRCReview = false
    var showDiagnostics = false
    var showCancelWarning = false
    var readback = ""
    var prepared: PreparedDisc?
    @ObservationIgnored private var operation: Task<Void, Never>?

    var album: AlbumModel {
        get { albums.indices.contains(selectedIndex) ? albums[selectedIndex] : AlbumModel() }
        set { if albums.indices.contains(selectedIndex) { albums[selectedIndex] = newValue; invalidate() } }
    }
    var hasAlbum: Bool { !album.tracks.isEmpty }
    var selectedDrive: DiscDrive? { drives.first { $0.id == driveID } }
    var speedDrive: DiscDrive? {
        backend == "cdrdao" ? drives.first { $0.id == cdrdaoDevice } : selectedDrive
    }
    var availableSpeeds: [Double] {
        BurnSpeedPolicy.available(speedDrive?.speeds ?? [], integerOnly: backend == "cdrdao")
    }
    var speedUnavailableReason: String {
        guard let drive = speedDrive else { return "Connect and select a CD writer to load supported speeds." }
        if !drive.present { return "Insert a blank CD-R to load supported speeds." }
        if drive.busy { return "The writer is reading the disc. Supported speeds will refresh when it is ready." }
        if !drive.blank { return "The inserted disc is not blank. Insert a blank CD-R for burning." }
        if backend == "cdrdao" && !drive.supportedSpeeds.isEmpty && availableSpeeds.isEmpty {
            return "cdrdao cannot represent the reported speeds. Choose DiscRecording."
        }
        return "The writer detected the blank disc but did not report supported speeds. Refresh the writer status."
    }
    func updateSpeedSelection() {
        speed = BurnSpeedPolicy.selection(speed, reported: availableSpeeds)
    }
    var tools: BackendTools {
        BackendTools(ffmpeg: ffmpegPath.isEmpty ? nil : URL(fileURLWithPath: ffmpegPath), ffprobe: ffprobePath.isEmpty ? nil : URL(fileURLWithPath: ffprobePath), cdrdao: cdrdaoPath.isEmpty ? nil : URL(fileURLWithPath: cdrdaoPath))
    }
    var textResult: Result<CDText, Error> { Result { try MetadataMapper.cdText(album, policy: policy) } }
    var estimatedLayout: DiscLayout { prepared?.layout ?? AudioConversionService.estimatedLayout(album, gapSeconds: gapSeconds) }
    var capacity: Int64 { min(Int64(capacityMinutes * 60 * 75), selectedDrive?.capacity ?? Int64(capacityMinutes * 60 * 75)) }
    var planningCapacity: Int64 { Int64(capacityMinutes * 60 * 75) }
    var canBurn: Bool {
        hasAlbum && !busy && speedDrive?.ready == true && availableSpeeds.contains(speed) && (backend == "DiscRecording" || tools.cdrdao != nil) && (try? textResult.get()) != nil
    }
    func applyISRCChoice(_ choice: ISRCBulkChoice) {
        guard hasAlbum, !busy else { return }
        var updated = album
        let count = ISRCReview.apply(choice, to: &updated)
        guard count > 0 else { return }
        album = updated
        log("ISRC choice updated for \(count) track(s); original FLAC tags are unchanged.")
    }
    func invalidate() {
        guard !burning else { return }
        prepared?.remove(); prepared = nil
    }
    func log(_ value: String) {
        guard logs.last != value else { return }
        logs.append(value); if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }
    var reporter: ProgressHandler {
        { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                if self.progress.stage != value.stage { self.log("\(value.stage): \(value.detail)") }
                self.progress = value
            }
        }
    }
    func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil; resultMessage = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.burning = false; self.operation = nil }
            do { try await body() }
            catch is CancellationError { self.progress = OperationProgress("Cancelled", "Operation stopped. A cancelled physical burn may leave the disc unusable."); self.log(self.progress.detail) }
            catch { let message = CDScribeError.describe(error); self.errorMessage = message; self.progress = OperationProgress("Stopped", message); self.log(message) }
        }
    }
    func importURLs(_ urls: [URL]) {
        run {
            let imported = try await AlbumImportService(tools: self.tools).importURLs(urls, progress: self.reporter)
            self.invalidate(); self.albums = imported; self.selectedIndex = 0; self.selection = nil
            self.progress = OperationProgress("Ready", "\(self.album.tracks.count) tracks imported • metadata populated automatically", fraction: 1)
            self.log("Imported \(imported.count) album/disc group(s); source files were read only.")
        }
    }
    func openFiles(folder: Bool = false) {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = folder ? "Open Album Folder" : "Open FLAC Files"
        panel.canChooseFiles = !folder; panel.canChooseDirectories = folder; panel.allowsMultipleSelection = !folder
        if !folder { panel.allowedContentTypes = [.init(filenameExtension: "flac")! ] }
        panel.begin { [weak self] response in
            Task { @MainActor in if response == .OK { self?.importURLs(panel.urls) } }
        }
    }
    func prepare() {
        guard hasAlbum else { return }
        run { try await self.prepareIfNeeded() }
    }
    private func prepareIfNeeded() async throws {
        if prepared != nil { return }
        let text = try textResult.get()
        _ = try NativeBurningService.validateText(text)
        let snapshot = album, tools = tools, gap = gapSeconds, capacity = planningCapacity
        prepared = try await AudioConversionService(tools: tools).prepare(snapshot, text: text, gapSeconds: gap, capacity: capacity, progress: reporter)
        log("Prepared \(prepared!.layout.audioFrames) audio frames; \(prepared!.layout.paddingFrames) zero frames added only at the disc end.")
    }
    func burn() {
        guard canBurn else { return }
        let chosenBackend = backend
        let identifier = chosenBackend == "DiscRecording" ? driveID : cdrdaoDevice
        let chosenSpeed = speed
        run {
            try await self.prepareIfNeeded()
            try await self.refreshDrives()
            guard let currentDrive = self.drives.first(where: { $0.id == identifier }), currentDrive.ready else {
                throw CDScribeError.message("The selected writer or blank disc is no longer ready. Refresh the writer status before burning.")
            }
            try BurnSpeedPolicy.validate(chosenSpeed, reported: currentDrive.speeds, integerOnly: chosenBackend == "cdrdao")
            guard let disc = self.prepared else { return }
            if self.backend == "DiscRecording" {
                guard let drive = self.selectedDrive, drive.ready else { throw CDScribeError.message("The selected drive is not ready. Insert a blank CD-R and refresh the drive status.") }
                try disc.layout.validate(capacity: min(self.planningCapacity, drive.capacity))
            }
            self.burning = true
            let service: any BurningService
            if self.backend == "cdrdao", let path = self.tools.cdrdao { service = CdrdaoBurningService(executable: path) }
            else { service = NativeBurningService() }
            let result = try await service.burn(disc, options: BurnOptions(driveID: identifier, speed: chosenSpeed, verify: self.verify), progress: self.reporter)
            self.resultMessage = result.message; self.log(result.message)
            self.progress = OperationProgress("Finished", result.message, fraction: 1)
        }
    }
    func cancel() { if burning { showCancelWarning = true } else { operation?.cancel() } }
    func confirmCancel() { operation?.cancel() }
    func attemptQuit() {
        if busy {
            let alert = NSAlert()
            alert.messageText = burning ? "A physical burn is still active" : "CDScribe is still preparing your disc"
            alert.informativeText = "Cancel or abort the operation in the window and wait for it to stop before quitting."
            alert.addButton(withTitle: "Keep CDScribe Open"); alert.runModal()
            return
        }
        invalidate(); NSApplication.shared.terminate(nil)
    }
    func moveTrack(_ delta: Int) {
        guard !busy, let selection, let index = album.tracks.firstIndex(where: { $0.id == selection }), album.tracks.indices.contains(index + delta) else { return }
        var updated = album; updated.tracks.swapAt(index, index + delta); album = updated
    }
    func refreshDrives() async throws {
        guard !burning else { return }
        drives = try await DiscDriveService().discover()
        if !drives.contains(where: { $0.id == driveID }) { driveID = drives.first?.id ?? "" }
        updateSpeedSelection()
    }
    func refreshDiagnostics() {
        Task { diagnostics = await DiscDriveService().diagnostics(tools: tools); log(diagnostics) }
    }
    func saveSettings() {
        for (key, value) in [("ffmpegPath", ffmpegPath), ("ffprobePath", ffprobePath), ("cdrdaoPath", cdrdaoPath)] { UserDefaults.standard.set(value, forKey: key) }
        invalidate(); refreshDiagnostics()
    }
    func exportPrepared() {
        guard !busy, let prepared else { return }
        let panel = NSOpenPanel(); panel.title = "Export Prepared Audio CD"; panel.prompt = "Export"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard response == .OK, let folder = panel.url else { return }
                do {
                    let destination = folder.appendingPathComponent("CDScribe-\(UUID().uuidString.prefix(8))")
                    try FileManager.default.copyItem(at: prepared.directory, to: destination)
                    NSWorkspace.shared.activateFileViewerSelecting([destination]); self?.log("Exported to \(destination.path)")
                } catch { self?.errorMessage = error.localizedDescription }
            }
        }
    }
    func readCDText() {
        guard let drive = selectedDrive else { return }
        run {
            self.progress = OperationProgress("Verifying", "Reading physical CD-Text")
            self.readback = try await VerificationService().readText(deviceID: drive.id)
            self.log("Physical CD-Text readback:\n\(self.readback)"); self.showDiagnostics = true
            self.progress = OperationProgress("Readback complete", "Actual on-disc CD-Text is shown in Diagnostics", fraction: 1)
        }
    }
}
