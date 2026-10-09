// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct ISRCReviewRow: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let number: Int
    public let title: String
    public let source: String
    public let output: String
    public let status: String
    public let problem: String?
    public let malformedSourceValues: [String]
}

public struct RepeatedISRC: Sendable, Equatable {
    public let code: String
    public let trackNumbers: [Int]
}

public enum ISRCBulkChoice: Sendable {
    case taggedValue(Int)
    case suppliedCode(String)
    case omitAll
    case resetAll
}

/// Local tag checks do not establish registration or identify the recording.
public enum ISRCReview {
    public static func rows(_ album: AlbumModel) -> [ISRCReviewRow] {
        album.tracks.enumerated().map { index, track in
            let malformed = MetadataMapper.isrcValues(track.isrc).filter { MetadataMapper.validISRC($0) == nil }
            do {
                let output = try MetadataMapper.discISRC(track)
                let status = output.isEmpty ? (track.isrcSelection == "" ? "Omitted by choice" : (MetadataMapper.isrcValues(track.isrc).count > 1 ? "Multiple values · omitted" : "No code")) : "Format valid · registration unchecked"
                return ISRCReviewRow(id: track.id, number: index + 1, title: track.title, source: track.isrc, output: output, status: status, problem: nil, malformedSourceValues: malformed)
            } catch {
                return ISRCReviewRow(id: track.id, number: index + 1, title: track.title, source: track.isrc, output: "", status: "Needs correction", problem: error.localizedDescription, malformedSourceValues: malformed)
            }
        }
    }
    public static func repeatedCodes(_ album: AlbumModel, onDisc: Bool) -> [RepeatedISRC] {
        var occurrences: [String: [Int]] = [:]
        for (index, track) in album.tracks.enumerated() {
            let codes: [String]
            if onDisc { codes = (try? MetadataMapper.discISRC(track)).flatMap { $0.isEmpty ? nil : [$0] } ?? [] }
            else { codes = track.isrcCandidates }
            for code in codes { occurrences[code, default: []].append(index + 1) }
        }
        return occurrences.filter { $0.value.count > 1 }.map { RepeatedISRC(code: $0.key, trackNumbers: $0.value) }.sorted { $0.code < $1.code }
    }
    public static func warnings(_ album: AlbumModel) -> [String] {
        let source = repeatedCodes(album, onDisc: false), output = repeatedCodes(album, onDisc: true)
        var warnings: [String] = []
        if !source.isEmpty {
            warnings.append("Source tags repeat ISRC values across tracks. An ISRC identifies a recording, not an album. Different songs sharing a code may have incorrect tags; check the recording details or omit ISRC.")
        }
        for repeated in output {
            warnings.append("On-disc ISRC \(repeated.code) is selected for tracks \(repeated.trackNumbers.map(String.init).joined(separator: ", ")). Review whether they are the same recording.")
        }
        return warnings
    }
    public static func commonCodes(_ album: AlbumModel) -> [String] {
        let tracks = album.tracks.filter { MetadataMapper.isrcValues($0.isrc).count > 1 }
        guard let first = tracks.first else { return [] }
        return first.isrcCandidates.filter { code in tracks.allSatisfy { $0.isrcCandidates.contains(code) } }
    }
    public static func availablePositions(_ album: AlbumModel) -> [Int] {
        let tracks = album.tracks.filter { MetadataMapper.isrcValues($0.isrc).count > 1 }
        let maximum = tracks.map { MetadataMapper.isrcValues($0.isrc).count }.max() ?? 0
        return (0..<maximum).filter { position in
            tracks.contains { track in
                let values = MetadataMapper.isrcValues(track.isrc)
                return values.indices.contains(position) && MetadataMapper.validISRC(values[position]) != nil
            }
        }
    }
    /// Uses each track's own ordered tag values; never copies a code to an unrelated track.
    @discardableResult public static func apply(_ choice: ISRCBulkChoice, to album: inout AlbumModel) -> Int {
        var count = 0
        for index in album.tracks.indices {
            let track = album.tracks[index], values = MetadataMapper.isrcValues(track.isrc)
            let selection: String?
            switch choice {
            case .omitAll: selection = ""
            case .resetAll: selection = nil
            case .taggedValue(let position):
                guard values.count > 1, values.indices.contains(position), let code = MetadataMapper.validISRC(values[position]) else { continue }
                selection = code
            case .suppliedCode(let supplied):
                guard values.count > 1, let code = MetadataMapper.validISRC(supplied), track.isrcCandidates.contains(code) else { continue }
                selection = code
            }
            if album.tracks[index].isrcSelection != selection {
                album.tracks[index].isrcSelection = selection; count += 1
            }
        }
        return count
    }
}
