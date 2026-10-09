// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// A bounded reader for STREAMINFO and PICTURE; tag decoding is provided by FFmpeg's libavformat.
public struct FLACHeader: Sendable {
    public var sampleFrames: Int64 = 0
    public var sampleRate: Int = 0
    public var channels: Int = 0
    public var bits: Int = 0
    public var artwork: Data?
    public static func read(_ url: URL) throws -> FLACHeader {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        func read(_ count: Int) throws -> Data {
            let data = try file.read(upToCount: count) ?? Data()
            guard data.count == count else { throw CDScribeError.message("Truncated FLAC metadata: \(url.lastPathComponent)") }
            return data
        }
        guard try read(4) == Data("fLaC".utf8) else { throw CDScribeError.message("Not a native FLAC file: \(url.lastPathComponent)") }
        var result = FLACHeader(), last = false, total = 0, blocks = 0
        while !last {
            let header = try read(4); last = header[0] & 0x80 != 0
            let type = header[0] & 0x7f
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            total += length; blocks += 1
            guard total <= 64 * 1024 * 1024, blocks <= 4096 else { throw CDScribeError.message("FLAC metadata exceeds the safe import limit.") }
            let data = try read(length)
            if blocks == 1 {
                guard type == 0, length == 34 else { throw CDScribeError.message("Missing FLAC STREAMINFO.") }
                let packed = data[10..<18].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                result.sampleRate = Int(packed >> 44)
                result.channels = Int((packed >> 41) & 7) + 1
                result.bits = Int((packed >> 36) & 31) + 1
                result.sampleFrames = Int64(packed & 0xfffffffff)
            }
            if type == 6 {
                var cursor = 0
                func integer() throws -> Int {
                    guard cursor + 4 <= data.count else { throw CDScribeError.message("Malformed FLAC artwork.") }
                    let value = data[cursor..<cursor+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    cursor += 4; return Int(value)
                }
                func skip(_ count: Int) throws {
                    guard count <= data.count - cursor else { throw CDScribeError.message("Malformed FLAC artwork length.") }
                    cursor += count
                }
                let pictureType = try integer()
                try skip(integer()); try skip(integer())
                for _ in 0..<4 { _ = try integer() }
                let imageLength = try integer()
                guard imageLength > 0, imageLength <= data.count - cursor else { throw CDScribeError.message("Malformed FLAC artwork payload.") }
                if result.artwork == nil || pictureType == 3 { result.artwork = data.subdata(in: cursor..<cursor+imageLength) }
            }
        }
        guard result.sampleRate > 0, result.sampleFrames > 0 else { throw CDScribeError.message("FLAC has no known audio length: \(url.lastPathComponent)") }
        return result
    }
}

private struct Probe: Decodable {
    struct Stream: Decodable {
        var codec_name: String?
        var codec_type: String?
        var tags: [String: String]?
    }
    struct Format: Decodable { var tags: [String: String]? }
    var streams: [Stream]
    var format: Format?
}

public struct AlbumImportService: Sendable {
    public let tools: BackendTools
    public init(tools: BackendTools = BackendTools()) { self.tools = tools }
    private static func collectFiles(_ urls: [URL]) throws -> Set<URL> {
        var files = Set<URL>()
        for input in urls {
            let url = input.standardizedFileURL.resolvingSymlinksInPath()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let child as URL in iterator where child.pathExtension.lowercased() == "flac" {
                    let info = try child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if info.isRegularFile == true && info.isSymbolicLink != true { files.insert(child.standardizedFileURL) }
                }
            } else if url.pathExtension.lowercased() == "flac" { files.insert(url) }
        }
        return files
    }
    public func importURLs(_ urls: [URL], progress: ProgressHandler? = nil) async throws -> [AlbumModel] {
        guard let ffprobe = tools.ffprobe else { throw CDScribeError.message("FFprobe is missing. Install the free FFmpeg dependency or choose its path in Settings.") }
        let files = try await Task.detached { try Self.collectFiles(urls) }.value
        guard !files.isEmpty else { throw CDScribeError.message("No FLAC files were found. Choose FLAC files or an album folder.") }
        guard files.count <= 999 else { throw CDScribeError.message("Import one album or a small collection of discs at a time (up to 999 tracks).") }
        var imported: [(TrackModel, Data?)] = []
        for (index, url) in files.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }).enumerated() {
            try Task.checkCancellation()
            progress?(OperationProgress("Reading metadata", url.lastPathComponent, fraction: Double(index) / Double(files.count)))
            let header = try await Task.detached { try FLACHeader.read(url) }.value
            let result = try await ProcessRunner().checked(ffprobe, ["-v", "error", "-show_format", "-show_streams", "-of", "json", url.path])
            let probe = try JSONDecoder().decode(Probe.self, from: result.output)
            guard let audio = probe.streams.first(where: { $0.codec_type == "audio" }), audio.codec_name == "flac" else { throw CDScribeError.message("The file does not contain FLAC audio: \(url.lastPathComponent)") }
            var tags: [String: String] = [:]
            for dictionary in [audio.tags ?? [:], probe.format?.tags ?? [:]] {
                for (key, value) in dictionary { tags[key.uppercased().replacingOccurrences(of: "_", with: "")] = value.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            let title = tags["TITLE"].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
            let albumArtist = tags["ALBUMARTIST"] ?? ""
            let artist = tags["ARTIST"].flatMap { $0.isEmpty ? nil : $0 } ?? albumArtist
            var warnings: [String] = []
            if tags["TITLE"]?.isEmpty != false { warnings.append("Title uses the filename") }
            if artist.isEmpty { warnings.append("Missing artist") }
            if tags["ALBUM"]?.isEmpty != false { warnings.append("Album uses the folder name") }
            let number = MetadataMapper.number(tags["TRACKNUMBER"] ?? tags["TRACK"])
            if number == nil { warnings.append("Missing track number; natural filename order used") }
            let isrc = tags["ISRC"] ?? ""
            let track = TrackModel(source: url, title: title, artist: artist, album: tags["ALBUM"].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingLastPathComponent().lastPathComponent, albumArtist: albumArtist, trackNumber: number, discNumber: MetadataMapper.number(tags["DISCNUMBER"] ?? tags["DISC"]) ?? 1, isrc: isrc, sampleRate: header.sampleRate, sampleFrames: header.sampleFrames, channels: header.channels, bitsPerSample: header.bits, warnings: warnings)
            imported.append((track, header.artwork))
        }
        progress?(OperationProgress("Reading metadata", "\(files.count) tracks imported", fraction: 1))
        let groups = Dictionary(grouping: imported) { "\($0.0.album)\u{0}\($0.0.albumArtist)\u{0}\($0.0.discNumber)" }
        return groups.values.map { group in
            let tracks = MetadataMapper.sorted(group.map(\.0))
            let first = tracks[0]
            let artists = Set(tracks.map(\.artist).filter { !$0.isEmpty })
            let artist = first.albumArtist.isEmpty ? (artists.count == 1 ? artists.first! : (artists.isEmpty ? "" : "Various Artists")) : first.albumArtist
            var warnings: [String] = []
            if artists.count > 1 && first.albumArtist.isEmpty { warnings.append("Compilation: disc performer defaults to Various Artists; each track keeps its own artist.") }
            if Set(tracks.compactMap(\.trackNumber)).count != tracks.compactMap(\.trackNumber).count { warnings.append("Duplicate track numbers; review the order.") }
            return AlbumModel(title: first.album, artist: artist, discNumber: first.discNumber, tracks: tracks, artwork: group.compactMap(\.1).first, warnings: warnings)
        }.sorted { ($0.title, $0.discNumber) < ($1.title, $1.discNumber) }
    }
}
