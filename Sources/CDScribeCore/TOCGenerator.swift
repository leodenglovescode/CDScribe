// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct LayoutTrack: Sendable, Equatable, Codable {
    public var startSector: Int64
    public var sectors: Int64
    public var pregapSectors: Int64
    public var wavName: String
    public init(startSector: Int64, sectors: Int64, pregapSectors: Int64 = 0, wavName: String = "") {
        self.startSector = startSector; self.sectors = sectors; self.pregapSectors = pregapSectors; self.wavName = wavName
    }
}
public struct DiscLayout: Sendable, Equatable, Codable {
    public var tracks: [LayoutTrack]
    public var imageName: String
    public var audioFrames: Int64
    public var totalSectors: Int64 { tracks.reduce(0) { $0 + $1.sectors + $1.pregapSectors } }
    public var duration: Double { Double(totalSectors) / 75 }
    public var paddingFrames: Int64 { tracks.reduce(0) { $0 + $1.sectors } * 588 - audioFrames }
    public init(tracks: [LayoutTrack], imageName: String = "audio.cdr", audioFrames: Int64) {
        self.tracks = tracks; self.imageName = imageName; self.audioFrames = audioFrames
    }
    public func validate(capacity: Int64 = CDDA.capacity80) throws {
        guard (1...99).contains(tracks.count) else { throw CDScribeError.message("An audio CD must contain 1–99 tracks.") }
        guard paddingFrames >= 0, paddingFrames < 588 else { throw CDScribeError.message("Invalid end-of-disc padding.") }
        var end: Int64 = 0
        for (index, track) in tracks.enumerated() {
            guard track.startSector == end, track.sectors >= 300, track.pregapSectors >= 0, track.pregapSectors <= 30 * 75 else { throw CDScribeError.message("Track \(index + 1) has an invalid boundary or is shorter than the Red Book minimum of four seconds.") }
            guard index != 0 || track.pregapSectors == 150 else { throw CDScribeError.message("The first track must have its mandatory two-second pregap.") }
            end += track.sectors
        }
        guard totalSectors <= capacity else { throw CDScribeError.message("The disc requires \(CDDA.time(duration)), exceeding the selected/media capacity of \(CDDA.time(Double(capacity) / 75)). Nothing will be truncated.") }
    }
}

public enum TOCGenerator {
    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    public static func render(text: CDText, layout: DiscLayout) throws -> String {
        guard text.tracks.count == layout.tracks.count else { throw CDScribeError.message("CD-Text and audio track counts do not match.") }
        // Numeric staged filenames isolate the TOC grammar from arbitrary source paths.
        guard layout.imageName.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw CDScribeError.message("Unsafe image filename.") }
        var toc = "CD_DA\n\nCD_TEXT {\n  LANGUAGE_MAP { 0 : EN }\n  LANGUAGE 0 {\n    TITLE \"\(escape(text.title))\"\n    PERFORMER \"\(escape(text.performer))\"\n  }\n}\n"
        for (index, track) in layout.tracks.enumerated() {
            let metadata = text.tracks[index]
            toc += "\n// Track \(index + 1)\nTRACK AUDIO\nNO COPY\nNO PRE_EMPHASIS\nTWO_CHANNEL_AUDIO\n"
            if !metadata.isrc.isEmpty { toc += "ISRC \"\(metadata.isrc)\"\n" }
            toc += "CD_TEXT {\n  LANGUAGE 0 {\n    TITLE \"\(escape(metadata.title))\"\n    PERFORMER \"\(escape(metadata.performer))\"\n  }\n}\n"
            if track.pregapSectors > 0 { toc += "PREGAP \(CDDA.msf(track.pregapSectors))\n" }
            toc += "FILE \"\(layout.imageName)\" \(CDDA.msf(track.startSector)) \(CDDA.msf(track.sectors))\n"
        }
        return toc
    }
    public static func write(text: CDText, layout: DiscLayout, to url: URL) throws {
        let toc = try render(text: text, layout: layout)
        guard let bytes = toc.data(using: text.encoding == "latin1" ? .isoLatin1 : .ascii, allowLossyConversion: false) else { throw CDScribeError.message("CD-Text cannot be encoded losslessly.") }
        try bytes.write(to: url, options: .atomic)
    }
}
