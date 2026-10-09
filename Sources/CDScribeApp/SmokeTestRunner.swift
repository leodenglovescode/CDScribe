// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CDScribeCore

extension AppModel {
    // Developer-only launch option. Exercises the real GUI model and preparation;
    // never starts a writer, touches media, or substitutes mock data in normal use.
    func runSmokeTestIfRequested() async {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--smoke-test"), index + 2 < args.count else { return }
        let folder = URL(fileURLWithPath: args[index + 1]), output = URL(fileURLWithPath: args[index + 2])
        if args.contains("--smoke-light") { NSApplication.shared.appearance = NSAppearance(named: .aqua) }
        var report: [String: Any] = ["physicalDiscWritten": false, "fixtureFolder": folder.path, "burnEnabledBeforeImport": canBurn]
        busy = true
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            report["stage"] = "Importing"
            let imported = try await AlbumImportService(tools: tools).importURLs([folder], progress: reporter)
            albums = imported; selectedIndex = 0
            report["album"] = album.title; report["artist"] = album.artist
            report["trackTitles"] = album.tracks.map(\.title)
            let text = try MetadataMapper.cdText(album, policy: policy)
            report["stage"] = "Preparing"
            prepared = try await AudioConversionService(tools: tools).prepare(album, text: text, gapSeconds: gapSeconds, progress: reporter)
            report["stage"] = "Discovering drives"
            try await refreshDrives()
            report["album"] = album.title; report["artist"] = album.artist
            report["trackTitles"] = album.tracks.map(\.title)
            report["cdtext"] = String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
            report["audioFrames"] = prepared!.layout.audioFrames
            report["sectors"] = prepared!.layout.totalSectors
            report["driveSnapshots"] = String(decoding: try JSONEncoder().encode(drives), as: UTF8.self)
            report["diagnostics"] = await DiscDriveService().diagnostics(tools: tools)
            try FileManager.default.copyItem(at: prepared!.directory, to: output.appendingPathComponent("Prepared Disc"))
            progress = OperationProgress("Ready", "Smoke test prepared real audio and CD-Text; no disc was written", fraction: 1)
            busy = false
            report["availableSpeeds"] = availableSpeeds
            report["selectedSpeed"] = speed
            report["selectedDriveReady"] = selectedDrive?.ready ?? false
            report["burnEnabledAfterPreparation"] = canBurn
            if args.contains("--smoke-isrc-review") {
                guard let code = ISRCReview.commonCodes(album).last else { throw CDScribeError.message("ISRC smoke fixture has no common choices.") }
                let sourceValues = album.tracks.map(\.isrc)
                applyISRCChoice(.suppliedCode(code))
                report["bulkISRC"] = code
                report["sourceISRCValuesPreserved"] = album.tracks.map(\.isrc) == sourceValues
                report["onDiscISRCs"] = ISRCReview.rows(album).map(\.output)
                report["isrcWarnings"] = ISRCReview.warnings(album)
                guard ISRCReview.rows(album).allSatisfy({ $0.output == code }) else { throw CDScribeError.message("Bulk ISRC selection failed in the GUI model.") }
                busy = true
                let chosenText = try MetadataMapper.cdText(album, policy: policy)
                prepared = try await AudioConversionService(tools: tools).prepare(album, text: chosenText, gapSeconds: gapSeconds, progress: reporter)
                try FileManager.default.copyItem(at: prepared!.directory, to: output.appendingPathComponent("Selected ISRC Disc"))
                report["selectedCDText"] = String(decoding: try JSONEncoder().encode(chosenText), as: UTF8.self)
                busy = false
            }
            try await Task.sleep(for: .milliseconds(500))
            let windows = NSApplication.shared.windows.filter { $0.isVisible && $0.title == "CDScribe" }
            report["visibleWindows"] = windows.count
            if let window = windows.first, let view = window.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let image = bitmap.representation(using: .png, properties: [:]) { try image.write(to: output.appendingPathComponent("window.png")) }
            }
            if args.contains("--smoke-isrc-review") { showISRCReview = true } else { showPreview = true }
            try await Task.sleep(for: .milliseconds(500))
            let preview = NSApplication.shared.windows.first { $0.isVisible && $0.sheetParent != nil }
            report["previewVisible"] = preview != nil
            report["previewWindowNumber"] = preview?.windowNumber
            if let view = preview?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let image = bitmap.representation(using: .png, properties: [:]) { try image.write(to: output.appendingPathComponent("cdtext-preview.png")) }
            }
            if !args.contains("--smoke-preview") { showPreview = false; showISRCReview = false }
            report["passed"] = !windows.isEmpty && preview != nil
        } catch {
            report["passed"] = false; report["error"] = String(describing: error)
            report["diagnostics"] = await DiscDriveService().diagnostics(tools: tools)
            busy = false; errorMessage = error.localizedDescription
        }
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json")) }
        catch { log("Smoke report could not be saved: \(error.localizedDescription)") }
    }
}
