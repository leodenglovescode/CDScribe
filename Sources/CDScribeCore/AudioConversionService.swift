// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct PreparedDisc: Sendable {
    public var directory: URL
    public var layout: DiscLayout
    public var text: CDText
    public var tocURL: URL { directory.appendingPathComponent("disc.toc") }
    public var audioURL: URL { directory.appendingPathComponent(layout.imageName) }
    public var wavURLs: [URL] { layout.tracks.map { directory.appendingPathComponent($0.wavName) } }
    public func remove() { try? FileManager.default.removeItem(at: directory) }
}

public struct AudioConversionService: Sendable {
    public let tools: BackendTools
    public init(tools: BackendTools = BackendTools()) { self.tools = tools }

    public static func estimatedLayout(_ album: AlbumModel, gapSeconds: Int) -> DiscLayout {
        var frames: Double = 0, endSector: Int64 = 0
        var tracks: [LayoutTrack] = []
        for (i, track) in album.tracks.enumerated() {
            frames += track.duration * 44100
            let sector = i == album.tracks.count - 1 ? CDDA.sectors(forFrames: Int64(frames.rounded())) : Int64((frames / 588).rounded())
            tracks.append(LayoutTrack(startSector: endSector, sectors: sector - endSector, pregapSectors: i == 0 ? 150 : Int64(gapSeconds * 75), wavName: String(format: "track-%02d.wav", i + 1)))
            endSector = sector
        }
        return DiscLayout(tracks: tracks, audioFrames: Int64(frames.rounded()))
    }

    public func prepare(_ album: AlbumModel, text: CDText, gapSeconds: Int = 0, capacity: Int64 = CDDA.capacity80, progress: ProgressHandler? = nil) async throws -> PreparedDisc {
        guard let ffmpeg = tools.ffmpeg else { throw CDScribeError.message("The bundled audio converter is missing. Download a fresh copy of CDScribe or check advanced executable settings.") }
        guard (0...30).contains(gapSeconds) else { throw CDScribeError.message("Track pauses must be between 0 and 30 seconds.") }
        try Self.estimatedLayout(album, gapSeconds: gapSeconds).validate(capacity: capacity)
        for track in album.tracks {
            guard (1...2).contains(track.channels) else { throw CDScribeError.message("\(track.title) has \(track.channels) channels. Explicitly downmix it to stereo before importing; CDScribe does not silently change surround mixes.") }
            guard [44100, 48000, 88200, 96000, 192000].contains(track.sampleRate) else { throw CDScribeError.message("Unsupported sample rate \(track.sampleRate) Hz for \(track.title).") }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CDScribe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let estimatedBytes = album.tracks.reduce(Int64(0)) { $0 + $1.sampleFrames * 8 } + Int64(album.duration * 44100 * 8) + (album.tracks.map { $0.sampleFrames * 8 }.max() ?? 0)
            let available = (try FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            guard available > estimatedBytes + 256 * 1024 * 1024 else { throw CDScribeError.message("Audio preparation needs about \(estimatedBytes / 1_000_000_000 + 1) GB of temporary disk space. Free some space and retry.") }
            let version = try await ProcessRunner().checked(ffmpeg, ["-version"])
            let useSoxr = String(decoding: version.output, as: UTF8.self).contains("--enable-libsoxr")
            let image = directory.appendingPathComponent("audio.cdr")
            _ = FileManager.default.createFile(atPath: image.path, contents: nil)
            let output = try FileHandle(forWritingTo: image); defer { try? output.close() }
            var boundaries: [Int64] = [], totalOutputFrames: Int64 = 0
            var groupStart = 0
            while groupStart < album.tracks.count {
                try Task.checkCancellation()
                let rate = album.tracks[groupStart].sampleRate
                var groupEnd = groupStart + 1
                while groupEnd < album.tracks.count && album.tracks[groupEnd].sampleRate == rate { groupEnd += 1 }
                let rawGroup = directory.appendingPathComponent("native.pcm")
                _ = FileManager.default.createFile(atPath: rawGroup.path, contents: nil)
                let rawHandle = try FileHandle(forWritingTo: rawGroup)
                var nativeFrames: Int64 = 0, groupBoundaries: [Int64] = []
                do {
                    for i in groupStart..<groupEnd {
                        let track = album.tracks[i]
                        let decoded = directory.appendingPathComponent("decoded.pcm")
                        progress?(OperationProgress("Decoding and converting audio", "Track \(i + 1) of \(album.tracks.count): \(track.title)", fraction: Double(i) / Double(album.tracks.count)))
                        _ = try await ProcessRunner().checked(ffmpeg, ["-nostdin", "-hide_banner", "-loglevel", "error", "-xerror", "-y", "-i", track.source.path, "-map", "0:a:0", "-vn", "-sn", "-dn", "-ac", "2", "-ar", String(rate), "-c:a", "pcm_s32le", "-f", "s32le", "-progress", "pipe:1", decoded.path], line: { line in
                            if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) {
                                progress?(OperationProgress("Decoding and converting audio", "Track \(i + 1): \(track.title)", fraction: (Double(i) + min(1, us / 1_000_000 / track.duration)) / Double(album.tracks.count)))
                            }
                        })
                        let size = try Self.size(decoded)
                        guard size == track.sampleFrames * 8 else { throw CDScribeError.message("Decoded length differs from the FLAC sample count for \(track.title). The file may be damaged or have changed since import.") }
                        try await Task.detached { try Self.copy(decoded, to: rawHandle) }.value
                        try FileManager.default.removeItem(at: decoded)
                        nativeFrames += track.sampleFrames
                        groupBoundaries.append(Int64((Double(nativeFrames) * 44100 / Double(rate)).rounded()))
                    }
                    try rawHandle.close()
                } catch { try? rawHandle.close(); throw error }
                let converted = directory.appendingPathComponent("converted.cdr")
                let needsDither = rate != 44100 || album.tracks[groupStart..<groupEnd].contains { $0.bitsPerSample > 16 }
                let filter = useSoxr ? "aresample=44100:resampler=soxr:precision=28:osf=s16:dither_method=\(needsDither ? "triangular" : "none")" : "aresample=44100:resampler=swr:filter_size=128:phase_shift=10:cutoff=0.97:osf=s16:dither_method=\(needsDither ? "triangular" : "none")"
                progress?(OperationProgress("Decoding and converting audio", "Resampling tracks \(groupStart + 1)–\(groupEnd) as one continuous stream"))
                let groupSeconds = Double(nativeFrames) / Double(rate)
                _ = try await ProcessRunner().checked(ffmpeg, ["-nostdin", "-hide_banner", "-loglevel", "error", "-xerror", "-y", "-f", "s32le", "-ar", String(rate), "-ac", "2", "-i", rawGroup.path, "-af", filter, "-c:a", "pcm_s16be", "-f", "s16be", "-progress", "pipe:1", converted.path], line: { line in
                    if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) {
                        progress?(OperationProgress("Decoding and converting audio", "Resampling continuous audio", fraction: min(1, us / 1_000_000 / groupSeconds)))
                    }
                })
                let convertedSize = try Self.size(converted)
                guard convertedSize > 0, convertedSize % 4 == 0 else { throw CDScribeError.message("The converter produced invalid CD-DA PCM.") }
                let frames = convertedSize / 4
                guard abs(frames - (groupBoundaries.last ?? 0)) <= 2 else { throw CDScribeError.message("Resampled duration differs from the expected sample count.") }
                for boundary in groupBoundaries.dropLast() { boundaries.append(totalOutputFrames + boundary) }
                totalOutputFrames += frames; boundaries.append(totalOutputFrames)
                try await Task.detached { try Self.copy(converted, to: output) }.value
                try FileManager.default.removeItem(at: rawGroup); try FileManager.default.removeItem(at: converted)
                groupStart = groupEnd
            }
            let totalSectors = CDDA.sectors(forFrames: totalOutputFrames)
            let padding = totalSectors * 588 - totalOutputFrames
            if padding > 0 { try output.write(contentsOf: Data(repeating: 0, count: Int(padding * 4))) }
            try output.synchronize()
            var tracks: [LayoutTrack] = [], previous: Int64 = 0
            for (i, boundary) in boundaries.enumerated() {
                let sector = i == boundaries.count - 1 ? totalSectors : Int64((Double(boundary) / 588).rounded())
                tracks.append(LayoutTrack(startSector: previous, sectors: sector - previous, pregapSectors: i == 0 ? 150 : Int64(gapSeconds * 75), wavName: String(format: "track-%02d.wav", i + 1)))
                previous = sector
            }
            let layout = DiscLayout(tracks: tracks, audioFrames: totalOutputFrames)
            try layout.validate(capacity: capacity)
            guard try Self.size(image) == totalSectors * 2352 else { throw CDScribeError.message("The prepared image is not sector aligned.") }
            progress?(OperationProgress("Validating disc layout", "Checking sector boundaries and native audio producers"))
            try await Task.detached {
                for track in layout.tracks { try Self.makeWAV(image: image, track: track, directory: directory) }
            }.value
            try Task.checkCancellation()
            progress?(OperationProgress("Generating CD-Text", "Writing album and track metadata"))
            try TOCGenerator.write(text: text, layout: layout, to: directory.appendingPathComponent("disc.toc"))
            let manifest = try JSONEncoder().encode(layout)
            try manifest.write(to: directory.appendingPathComponent("layout.json"))
            try JSONEncoder().encode(text).write(to: directory.appendingPathComponent("cdtext.json"))
            let prepared = PreparedDisc(directory: directory, layout: layout, text: text)
            try await NativeBurningService.validate(prepared)
            if let cdrdao = tools.cdrdao {
                progress?(OperationProgress("Validating disc layout", "cdrdao TOC parser and full PCM read test"))
                _ = try await ProcessRunner().checked(cdrdao, ["toc-info", "disc.toc"], directory: directory)
                _ = try await ProcessRunner().checked(cdrdao, ["read-test", "disc.toc"], directory: directory)
            }
            try Task.checkCancellation()
            progress?(OperationProgress("Ready", "\(tracks.count) tracks • \(CDDA.time(layout.duration)) • CD-Text validated", fraction: 1))
            return prepared
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    private static func size(_ url: URL) throws -> Int64 { (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber).int64Value }
    private static func copy(_ source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        while true {
            try Task.checkCancellation()
            let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }; try output.write(contentsOf: chunk)
        }
    }
    private static func makeWAV(image: URL, track: LayoutTrack, directory: URL) throws {
        let input = try FileHandle(forReadingFrom: image); defer { try? input.close() }
        try input.seek(toOffset: UInt64(track.startSector * 2352))
        let url = directory.appendingPathComponent(track.wavName)
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        let byteCount = UInt32(track.sectors * 2352)
        var header = Data("RIFF".utf8)
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        u32(byteCount + 36); header.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(2)
        u32(44100); u32(176400); u16(4); u16(16); header.append(Data("data".utf8)); u32(byteCount)
        try output.write(contentsOf: header)
        var remaining = Int(byteCount)
        while remaining > 0 {
            try Task.checkCancellation()
            var chunk = try input.read(upToCount: min(1024 * 1024, remaining)) ?? Data()
            guard !chunk.isEmpty, chunk.count % 2 == 0 else { throw CDScribeError.message("Truncated image while building WAV tracks.") }
            chunk.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                for i in stride(from: 0, to: bytes.count, by: 2) { let temp = bytes[i]; bytes[i] = bytes[i + 1]; bytes[i + 1] = temp }
            }
            try output.write(contentsOf: chunk); remaining -= chunk.count
        }
    }
}
