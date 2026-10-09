// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
@preconcurrency import NativeDisc

public struct BurnOptions: Sendable {
    public var driveID: String
    public var speed: Double
    public var verify: Bool
    public init(driveID: String, speed: Double = 0, verify: Bool = true) { self.driveID = driveID; self.speed = speed; self.verify = verify }
}
public struct BurnResult: Sendable {
    public var message: String
    public var audioVerified: Bool
    public var textVerified: Bool
    public var physicalDiscWritten: Bool
    public init(message: String, audioVerified: Bool = false, textVerified: Bool = false, physicalDiscWritten: Bool) {
        self.message = message; self.audioVerified = audioVerified; self.textVerified = textVerified; self.physicalDiscWritten = physicalDiscWritten
    }
}
@MainActor public protocol BurningService {
    func burn(_ disc: PreparedDisc, options: BurnOptions, progress: ProgressHandler?) async throws -> BurnResult
}

@MainActor public final class NativeBurningService: BurningService {
    public init() {}
    public nonisolated static func validate(_ disc: PreparedDisc) async throws {
        let textData = try JSONEncoder().encode(disc.text)
        try await Task.detached {
            _ = try CDNativeDisc.validatedText(textData)
            try CDNativeDisc.validateAudioPaths(disc.wavURLs.map(\.path), sectors: disc.layout.tracks.map { NSNumber(value: $0.sectors) })
        }.value
    }
    public nonisolated static func validateText(_ text: CDText) throws -> Data { try CDNativeDisc.validatedText(JSONEncoder().encode(text)) }
    public func burn(_ disc: PreparedDisc, options: BurnOptions, progress: ProgressHandler?) async throws -> BurnResult {
        try disc.layout.validate()
        try await Self.validate(disc)
        try Task.checkCancellation()
        let operation = CDNativeDisc()
        try operation.startDevice(options.driveID, paths: disc.wavURLs.map(\.path), sectors: disc.layout.tracks.map { NSNumber(value: $0.sectors) }, gaps: disc.layout.tracks.map { NSNumber(value: $0.pregapSectors) }, text: JSONEncoder().encode(disc.text), speed: options.speed, verify: options.verify)
        var cancelled = false
        while true {
            if Task.isCancelled && !cancelled { operation.abort(); cancelled = true }
            let status = try JSONDecoder().decode(NativeStatus.self, from: operation.burnStatus())
            progress?(OperationProgress(status.phase, cancelled ? "Abort requested; waiting for the writer to stop safely" : status.state, fraction: status.fraction))
            if status.failed {
                if cancelled { throw CancellationError() }
                throw CDScribeError.message("DiscRecording failed: \(status.error). The disc may be incomplete; review Diagnostics before retrying.")
            }
            if status.done {
                if cancelled { throw CDScribeError.message("The writer finished before cancellation took effect. A disc was written; verification was interrupted.") }
                var textVerified = false, verificationError = ""
                if options.verify {
                    progress?(OperationProgress("Verifying", "Reading physical CD-Text from the disc"))
                    do { try await VerificationService().verifyText(deviceID: options.driveID, expected: disc.text); textVerified = true }
                    catch { verificationError = " CD-Text readback could not be verified: \(error.localizedDescription)" }
                }
                let audioVerified = options.verify && status.verificationObserved
                let message = "DiscRecording confirmed the burn finished. " + (audioVerified ? "Audio verification completed." : "Audio readback is unverified.") + (textVerified ? " CD-Text readback matches the preview." : " CD-Text readback is unverified.") + verificationError
                return BurnResult(message: message, audioVerified: audioVerified, textVerified: textVerified, physicalDiscWritten: true)
            }
            // A cancelled parent must still wait for the physical writer's terminal status.
            await Task.detached { try? await Task.sleep(for: .milliseconds(300)) }.value
        }
    }
}
private struct NativeStatus: Decodable {
    var state: String
    var phase: String
    var done: Bool
    var failed: Bool
    var fraction: Double?
    var error: String
    var verificationObserved: Bool
}

@MainActor public final class CdrdaoBurningService: BurningService {
    let executable: URL
    public init(executable: URL) { self.executable = executable }
    public func burn(_ disc: PreparedDisc, options: BurnOptions, progress: ProgressHandler?) async throws -> BurnResult {
        guard !options.driveID.isEmpty, !options.driveID.hasPrefix("-") else { throw CDScribeError.message("Supply the exact cdrdao device identifier shown by scanbus in Diagnostics.") }
        // Preflight with the actual device. The GUI exposes this backend as experimental on macOS.
        let driveInfo = try await ProcessRunner().checked(executable, ["drive-info", "--device", options.driveID])
        let driveLog = String(decoding: driveInfo.output + driveInfo.errorOutput, as: UTF8.self)
        guard CdrdaoPreflight.supportsText(driveLog) else { throw CDScribeError.message("cdrdao did not confirm CD-Text support for this writer. Use DiscRecording or inspect Diagnostics.\n\(driveLog)") }
        let mediaInfo = try await ProcessRunner().checked(executable, ["disk-info", "--device", options.driveID])
        let mediaLog = String(decoding: mediaInfo.output + mediaInfo.errorOutput, as: UTF8.self)
        let capacity = try CdrdaoPreflight.blankCapacity(mediaLog)
        try disc.layout.validate(capacity: capacity)
        let drives = try await DiscDriveService().discover()
        guard let drive = drives.first(where: { $0.id == options.driveID }), drive.ready else {
            throw CDScribeError.message("cdrdao requires a ready writer whose current media speeds can be confirmed by DiscRecording. Nothing has been written.")
        }
        try BurnSpeedPolicy.validate(options.speed, reported: drive.speeds, integerOnly: true)
        var args = ["write", "--device", options.driveID, "--driver", "generic-mmc:0x10", "-n", "--speed", String(format: "%.0f", options.speed)]
        args += ["disc.toc"]
        progress?(OperationProgress("Burning", "cdrdao disc-at-once write"))
        _ = try await ProcessRunner().checked(executable, args, directory: disc.directory, line: { log in
            let stage = log.lowercased().contains("lead-out") ? "Finalizing" : "Burning"
            progress?(OperationProgress(stage, log))
        })
        var textVerified = false, detail = "CD-Text readback is unverified."
        if options.verify {
            progress?(OperationProgress("Verifying", "Reading physical CD-Text through the native device interface"))
            do { try await VerificationService().verifyText(deviceID: options.driveID, expected: disc.text); textVerified = true; detail = "CD-Text readback matches the preview." }
            catch { detail = "CD-Text readback could not be verified: \(error.localizedDescription)" }
        }
        return BurnResult(message: "cdrdao reported a completed write. Audio readback remains unverified. " + detail, textVerified: textVerified, physicalDiscWritten: true)
    }
}

public enum CdrdaoPreflight {
    public static func supportsText(_ log: String) -> Bool {
        log.range(of: "(?im)^\\s*CD[- ]TEXT writing (?:is )?supported\\.?\\s*$", options: .regularExpression) != nil ||
        log.range(of: "(?im)^\\s*CD[- ]TEXT writing\\s*:\\s*yes\\s*$", options: .regularExpression) != nil
    }
    public static func blankCapacity(_ log: String) throws -> Int64 {
        let blank = log.range(of: "(?im)^\\s*(?:disc|disk|medium|media)\\s*(?:status|state)\\s*:\\s*(?:empty|blank)\\s*$", options: .regularExpression) != nil ||
            log.range(of: "(?im)^\\s*(?:(?:disc|disk|medium|media)\\s+)?(?:is\\s+)?(?:empty|blank)\\s*:\\s*yes\\s*$", options: .regularExpression) != nil
        guard blank, log.range(of: "(?im)^\\s*(?:disc|disk|medium|media)\\s*type\\s*:\\s*CD-R(?:W)?\\s*$", options: .regularExpression) != nil,
              let line = log.split(separator: "\n").first(where: { $0.lowercased().contains("capacity") }),
              let range = line.range(of: "[0-9]+:[0-9]{2}:[0-9]{2}", options: .regularExpression) else {
            throw CDScribeError.message("cdrdao could not confirm blank CD media and its capacity. Nothing was written.\n\(log)")
        }
        let parts = line[range].split(separator: ":").compactMap { Int64($0) }
        guard parts.count == 3, parts[0] > 0, parts[0] <= 99, parts[1] < 60, parts[2] < 75 else { throw CDScribeError.message("Invalid cdrdao media capacity response.") }
        return parts[0] * 4500 + parts[1] * 75 + parts[2]
    }
}

// Deliberately separate from production backends; never reports a physical burn.
@MainActor public final class MockBurningService: BurningService {
    public init() {}
    public func burn(_ disc: PreparedDisc, options: BurnOptions, progress: ProgressHandler?) async throws -> BurnResult {
        try disc.layout.validate()
        _ = try TOCGenerator.render(text: disc.text, layout: disc.layout)
        progress?(OperationProgress("Mock validation", "No laser or hardware was used", fraction: 1))
        return BurnResult(message: "Mock layout validation passed; no physical disc was written.", physicalDiscWritten: false)
    }
}
