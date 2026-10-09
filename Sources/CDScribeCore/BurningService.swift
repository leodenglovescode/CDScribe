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
            try CDNativeDisc.validateAudioPaths(disc.wavURLs.map(\.path), sectors: disc.layout.tracks.map { NSNumber(value: $0.sectors) }, gaps: disc.layout.tracks.map { NSNumber(value: $0.pregapSectors) })
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
                throw status.failure
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
struct NativeStatus: Decodable {
    var state: String
    var phase: String
    var done: Bool
    var failed: Bool
    var fraction: Double?
    var error: String
    var verificationObserved: Bool
    var errorCode: Int64
    var pregapUnsupported: Bool
    var failure: CDScribeError {
        let details = "\(error) (code \(errorCode))"
        return pregapUnsupported ? .unsupportedNativePregap(details) : .message("DiscRecording failed: \(details). The disc may be incomplete; review Diagnostics before retrying.")
    }
}

@MainActor public final class CdrdaoBurningService: BurningService {
    let executable: URL
    public init(executable: URL) { self.executable = executable }
    /// Read-only checks shared by writing and hardware diagnostics. Never operates the laser.
    public func preflight(driveID: String, speed: Double) async throws -> CdrdaoMedia {
        guard !driveID.isEmpty, !driveID.hasPrefix("-") else { throw CDScribeError.message("Select a connected CD writer before using cdrdao.") }
        let driveInfo = try await ProcessRunner().checked(executable, ["drive-info", "--device", driveID])
        let driveLog = String(decoding: driveInfo.output + driveInfo.errorOutput, as: UTF8.self)
        guard CdrdaoPreflight.supportsText(driveLog) else { throw CDScribeError.message("cdrdao did not confirm CD-Text support for this writer. Inspect Diagnostics.\n\(driveLog)") }
        let mediaInfo = try await ProcessRunner().checked(executable, ["disk-info", "--device", driveID])
        let mediaLog = String(decoding: mediaInfo.output + mediaInfo.errorOutput, as: UTF8.self)
        let reportedCapacity = try CdrdaoPreflight.blankCapacity(mediaLog)
        // cdrdao briefly takes exclusive device access. DiscRecording can report
        // transitioning/no media just after the child exits; wait for fresh status
        // rather than reusing a stale pre-query speed list or rejecting too early.
        var readyDrive: DiscDrive?
        for attempt in 0..<24 {
            try Task.checkCancellation()
            let drives = try await DiscDriveService().discover()
            if let drive = drives.first(where: { $0.id == driveID }), drive.ready { readyDrive = drive; break }
            if attempt < 23 { try await Task.sleep(for: .milliseconds(250)) }
        }
        guard let drive = readyDrive else {
            throw CDScribeError.message("The writer did not become ready after cdrdao checked the disc. Refresh the disc status before retrying. Nothing has been written.")
        }
        try BurnSpeedPolicy.validate(speed, reported: drive.speeds, integerOnly: true)
        return CdrdaoMedia(capacity: min(reportedCapacity, drive.capacity), driveLog: driveLog, mediaLog: mediaLog)
    }
    public func burn(_ disc: PreparedDisc, options: BurnOptions, progress: ProgressHandler?) async throws -> BurnResult {
        let media = try await preflight(driveID: options.driveID, speed: options.speed)
        try disc.layout.validate(capacity: media.capacity)
        try Task.checkCancellation()
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

public struct CdrdaoMedia: Sendable {
    public var capacity: Int64
    public var driveLog: String
    public var mediaLog: String
}

public enum CdrdaoPreflight {
    public static func supportsText(_ log: String) -> Bool {
        log.range(of: "(?im)^\\s*CD[- ]TEXT writing (?:is )?supported\\.?\\s*$", options: .regularExpression) != nil ||
        log.range(of: "(?im)^\\s*CD[- ]TEXT writing\\s*:\\s*yes\\s*$", options: .regularExpression) != nil
    }
    public static func blankCapacity(_ log: String) throws -> Int64 {
        func matches(_ pattern: String) -> Bool { log.range(of: pattern, options: .regularExpression) != nil }
        // cdrdao 1.2.6 uses CD-RW: no/yes plus CD-R empty: yes on macOS.
        // Keep support for explicit type/state responses, but reject contradictory reports.
        let explicitCD = matches(#"(?im)^\s*(?:disc|disk|medium|media)\s*type\s*:\s*CD-R(?:W)?\s*$"#)
        let typedBlankCD = matches(#"(?im)^\s*CD-R(?:W)?\s+empty\s*:\s*yes\s*$"#)
        let actualCD = matches(#"(?im)^\s*CD-RW\s*:\s*(?:yes|no)\s*$"#) && typedBlankCD
        let blank = typedBlankCD || matches(#"(?im)^\s*(?:disc|disk|medium|media)\s*(?:status|state)\s*:\s*(?:empty|blank)\s*$"#) ||
            matches(#"(?im)^\s*(?:(?:disc|disk|medium|media)\s+)?(?:is\s+)?(?:empty|blank)\s*:\s*yes\s*$"#)
        let conflicting = matches(#"(?im)^\s*(?:disc|disk|medium|media)\s*type\s*:\s*(?!CD-R(?:W)?\s*$)\S.*$"#) ||
            matches(#"(?im)^\s*(?:CD-R(?:W)?\s+)?(?:empty|blank)\s*:\s*no\s*$"#) ||
            matches(#"(?im)^\s*(?:disc|disk|medium|media)\s*(?:status|state)\s*:\s*(?!empty\s*$|blank\s*$)\S.*$"#) ||
            (matches(#"(?im)^\s*CD-RW\s*:\s*yes\s*$"#) && matches(#"(?im)^\s*CD-RW\s*:\s*no\s*$"#))
        let pattern = #"(?im)^\s*Total Capacity\s*:\s*(\d{1,2}):(\d{2}):(\d{2})\s*(?:\((\d+)\s+blocks\b[^\n]*\))?\s*$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsLog = log as NSString
        let capacities = regex.matches(in: log, range: NSRange(location: 0, length: nsLog.length))
        guard blank, explicitCD || actualCD, !conflicting, capacities.count == 1 else {
            throw CDScribeError.message("cdrdao could not confirm blank CD media and its capacity. Nothing was written.\n\(log)")
        }
        let match = capacities[0]
        let parts = (1...3).compactMap { Int64(nsLog.substring(with: match.range(at: $0))) }
        guard parts.count == 3, parts[0] > 0, parts[0] <= 99, parts[1] < 60, parts[2] < 75 else { throw CDScribeError.message("Invalid cdrdao media capacity response.") }
        let sectors = parts[0] * 4500 + parts[1] * 75 + parts[2]
        if match.range(at: 4).location != NSNotFound {
            guard Int64(nsLog.substring(with: match.range(at: 4))) == sectors else { throw CDScribeError.message("cdrdao returned conflicting disc capacity values. Nothing was written.") }
        }
        return sectors
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
