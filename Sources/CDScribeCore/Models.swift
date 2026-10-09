// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum CDScribeError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    public static func describe(_ error: any Error) -> String {
        if error is DecodingError { return "The backend returned an unexpected response: \(String(describing: error))" }
        return error.localizedDescription
    }
}

public struct TrackModel: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: URL
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var trackNumber: Int?
    public var discNumber: Int
    /// Source tag text is retained even when it contains several identifiers.
    public var isrc: String { didSet { if oldValue != isrc { isrcSelection = nil } } }
    public var isrcSelection: String? = nil
    public var isrcCandidates: [String] { MetadataMapper.isrcValues(isrc).compactMap(MetadataMapper.validISRC) }
    public var metadataWarnings: [String] {
        var result = warnings
        let values = MetadataMapper.isrcValues(isrc)
        if values.count > 1 && isrcSelection == nil {
            result.append("Multiple ISRC values in the source tags. This optional field will be omitted unless you choose one in the ISRC menu; audio and title/artist CD-Text can still be written.")
        } else if isrcSelection == nil && values.contains(where: { MetadataMapper.validISRC($0) == nil }) {
            result.append("Invalid ISRC format; correct or clear this optional field before burning.")
        }
        return result
    }
    public let sampleRate: Int
    public let sampleFrames: Int64
    public let channels: Int
    public let bitsPerSample: Int
    public var warnings: [String]
    public var duration: Double { Double(sampleFrames) / Double(sampleRate) }
    public init(id: UUID = UUID(), source: URL, title: String, artist: String, album: String = "", albumArtist: String = "", trackNumber: Int? = nil, discNumber: Int = 1, isrc: String = "", sampleRate: Int = 44100, sampleFrames: Int64 = 44100 * 5, channels: Int = 2, bitsPerSample: Int = 16, warnings: [String] = []) {
        self.id = id; self.source = source; self.title = title; self.artist = artist
        self.album = album; self.albumArtist = albumArtist; self.trackNumber = trackNumber
        self.discNumber = discNumber; self.isrc = isrc; self.sampleRate = sampleRate
        self.sampleFrames = sampleFrames; self.channels = channels; self.bitsPerSample = bitsPerSample; self.warnings = warnings
    }
}

public struct AlbumModel: Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var title: String
    public var artist: String
    public var discNumber: Int
    public var tracks: [TrackModel]
    public var artwork: Data?
    public var warnings: [String]
    public var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
    public init(title: String = "", artist: String = "", discNumber: Int = 1, tracks: [TrackModel] = [], artwork: Data? = nil, warnings: [String] = []) {
        self.title = title; self.artist = artist; self.discNumber = discNumber; self.tracks = tracks; self.artwork = artwork; self.warnings = warnings
    }
}

public enum TextEncodingPolicy: String, CaseIterable, Identifiable, Sendable {
    case latin1 = "Latin-1 (strict)"
    case ascii = "ASCII (strict)"
    case transliterate = "Transliterate to ASCII"
    public var id: String { rawValue }
}

public struct CDTextTrack: Sendable, Equatable, Codable {
    public var title: String
    public var performer: String
    public var isrc: String
}

public struct CDText: Sendable, Equatable, Codable {
    public var title: String
    public var performer: String
    public var tracks: [CDTextTrack]
    public var encoding: String
    public var changes: [String]
}

public struct OperationProgress: Sendable {
    public var stage: String
    public var detail: String
    public var fraction: Double?
    public init(_ stage: String, _ detail: String, fraction: Double? = nil) {
        self.stage = stage; self.detail = detail; self.fraction = fraction.map { min(1, max(0, $0)) }
    }
}
public typealias ProgressHandler = @Sendable (OperationProgress) -> Void

public enum CDDA {
    public static let framesPerSector: Int64 = 588
    public static let bytesPerSector: Int64 = 2352
    public static let sectorsPerSecond: Int64 = 75
    public static let capacity74: Int64 = 74 * 60 * 75
    public static let capacity80: Int64 = 80 * 60 * 75
    public static func sectors(forFrames frames: Int64) -> Int64 { (frames + 587) / 588 }
    public static func time(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
    public static func msf(_ sectors: Int64) -> String {
        String(format: "%02lld:%02lld:%02lld", sectors / 4500, sectors / 75 % 60, sectors % 75)
    }
}
