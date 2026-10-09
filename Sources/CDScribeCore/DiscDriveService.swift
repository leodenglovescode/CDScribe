// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
@preconcurrency import NativeDisc

public struct DiscDrive: Identifiable, Sendable, Codable, Equatable {
    public var id: String
    public var name: String
    public var bsdName: String
    public var present: Bool
    public var blank: Bool
    public var busy: Bool
    public var mediaType: String
    public var capacity: Int64
    public var cdText: Bool
    public var sao: Bool
    public var speeds: [Double]
    public var supportedSpeeds: [Double] { BurnSpeedPolicy.available(speeds) }
    public var ready: Bool { present && blank && !busy && cdText && sao && ["CD-R", "CD-RW"].contains(mediaType) && capacity > 0 }
}

public struct DiscDriveService: Sendable {
    public init() {}
    public func discover() async throws -> [DiscDrive] {
        try await Task.detached { try JSONDecoder().decode([DiscDrive].self, from: CDNativeDisc.driveSnapshot()) }.value
    }
    public func diagnostics(tools: BackendTools) async -> String {
        var lines: [String] = []
        for (name, path) in [("FFmpeg", tools.ffmpeg), ("FFprobe", tools.ffprobe), ("cdrdao", tools.cdrdao)] {
            if let path {
                do {
                    let result = try await ProcessRunner().run(path, [name == "cdrdao" ? "version" : "-version"])
                    let message = String(decoding: result.output + result.errorOutput, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? "No output"
                    lines.append("\(name): \(path.path)\n\(message)")
                } catch { lines.append("\(name): \(error.localizedDescription)") }
            } else { lines.append("\(name): not installed") }
        }
        if let cdrdao = tools.cdrdao {
            do {
                let result = try await ProcessRunner().run(cdrdao, ["scanbus"])
                lines.append("cdrdao scanbus (exit \(result.status)):\n" + String(decoding: result.output + result.errorOutput, as: UTF8.self))
            } catch { lines.append("cdrdao scanbus: \(error.localizedDescription)") }
        }
        do {
            let drives = try await discover()
            lines.append("DiscRecording CD writers detected: \(drives.count)")
            for drive in drives {
                lines.append("\(drive.name)\n\(drive.id)\nMedia: \(drive.mediaType), blank: \(drive.blank), busy: \(drive.busy), capacity sectors: \(drive.capacity)\nCD-Text: \(drive.cdText), session-at-once: \(drive.sao)\nReported burn speeds: \(drive.supportedSpeeds.map(BurnSpeedPolicy.label).joined(separator: ", "))")
            }
        }
        catch { lines.append("DiscRecording: \(error.localizedDescription)") }
        return lines.joined(separator: "\n\n")
    }
}

/// Only explicit rates reported for the current drive/media may reach a writer.
public enum BurnSpeedPolicy {
    public static func available(_ reported: [Double], integerOnly: Bool = false) -> [Double] {
        Array(Set(reported.filter { $0.isFinite && $0 > 0 && (!integerOnly || $0.rounded() == $0) })).sorted()
    }
    public static func selection(_ selected: Double, reported: [Double], integerOnly: Bool = false) -> Double {
        let rates = available(reported, integerOnly: integerOnly)
        return rates.contains(selected) ? selected : (rates.first ?? 0)
    }
    public static func validate(_ selected: Double, reported: [Double], integerOnly: Bool = false) throws {
        guard selected.isFinite, selected > 0, available(reported, integerOnly: integerOnly).contains(selected) else {
            throw CDScribeError.message("The chosen burn speed is not reported for this writer and inserted disc. Refresh the writer status and choose an available speed. Nothing has been written.")
        }
    }
    public static func label(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(0...3))) + "×"
    }
}
