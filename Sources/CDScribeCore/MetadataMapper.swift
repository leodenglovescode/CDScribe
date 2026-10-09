// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum MetadataMapper {
    public static func number(_ value: String?) -> Int? {
        guard let value, let n = Int(value.split(separator: "/", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""), n > 0 else { return nil }; return n
    }
    public static func validISRC(_ value: String) -> String? {
        var code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if code.hasPrefix("ISRC ") { code = String(code.dropFirst(5)) }
        code = code.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        return code.range(of: "^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$", options: .regularExpression) != nil ? code : nil
    }
    /// Common taggers serialize repeated ISRC values with semicolons.
    public static func isrcValues(_ value: String) -> [String] {
        var seen = Set<String>()
        return value.components(separatedBy: CharacterSet(charactersIn: ";\n\r"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { validISRC($0) ?? $0 }
            .filter { seen.insert($0).inserted }
    }
    public static func discISRC(_ track: TrackModel) throws -> String {
        if let selection = track.isrcSelection {
            if selection.isEmpty { return "" }
            guard let code = validISRC(selection), track.isrcCandidates.contains(code) else {
                throw CDScribeError.message("The chosen ISRC is no longer in this track's tags. Choose it again or omit ISRC.")
            }
            return code
        }
        let values = isrcValues(track.isrc)
        // Ambiguous optional identifiers must not prevent audio or CD-Text writing.
        if values.count > 1 { return "" }
        guard let value = values.first else { return "" }
        guard let code = validISRC(value) else {
            throw CDScribeError.message("Invalid ISRC format: “\(value)”. Correct it or clear the optional ISRC field before burning.")
        }
        return code
    }
    public static func sorted(_ tracks: [TrackModel]) -> [TrackModel] {
        tracks.sorted {
            if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
            if $0.trackNumber != $1.trackNumber { return ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
            return $0.source.path.localizedStandardCompare($1.source.path) == .orderedAscending
        }
    }
    public static func cdText(_ album: AlbumModel, policy: TextEncodingPolicy) throws -> CDText {
        var changes: [String] = []
        func encode(_ text: String, _ label: String) throws -> String {
            var result = text.precomposedStringWithCanonicalMapping
            guard !result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw CDScribeError.message("\(label) contains a control character. Remove line breaks, tabs, or NUL characters.") }
            if policy == .transliterate {
                let replacements = ["“": "\"", "”": "\"", "‘": "'", "’": "'", "–": "-", "—": "-", "…": "...", "œ": "oe", "Œ": "OE", "ß": "ss"]
                for (a, b) in replacements { result = result.replacingOccurrences(of: a, with: b) }
                result = result.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? result
            }
            let encoding: String.Encoding = policy == .latin1 ? .isoLatin1 : .ascii
            guard result.data(using: encoding, allowLossyConversion: false) != nil else {
                throw CDScribeError.message("\(label) contains characters outside \(policy == .latin1 ? "CD-Text Latin-1" : "ASCII"): “\(text)”. Choose transliteration and review the preview, or edit this field. Source tags will stay untouched.")
            }
            if result != text { changes.append("\(label): “\(text)” → “\(result)”") }
            guard !result.isEmpty else { throw CDScribeError.message("\(label) is empty. Add it in the review table.") }
            return result
        }
        var tracks: [CDTextTrack] = []
        for (index, track) in album.tracks.enumerated() {
            let isrc: String
            do { isrc = try discISRC(track) }
            catch { throw CDScribeError.message("Track \(index + 1): \(error.localizedDescription)") }
            if isrc.isEmpty && isrcValues(track.isrc).count > 1 {
                changes.append("Track \(index + 1): multiple source ISRC values (\(track.isrc)). No ISRC will be written; choose one in the ISRC menu if you know which applies. Audio and title/artist CD-Text are unaffected.")
            }
            tracks.append(CDTextTrack(title: try encode(track.title.isEmpty ? track.source.deletingPathExtension().lastPathComponent : track.title, "Track \(index + 1) title"), performer: try encode(track.artist.isEmpty ? album.artist : track.artist, "Track \(index + 1) performer"), isrc: isrc))
        }
        changes.append(contentsOf: ISRCReview.warnings(album))
        return CDText(title: try encode(album.title, "Disc title"), performer: try encode(album.artist, "Disc performer"), tracks: tracks, encoding: policy == .latin1 ? "latin1" : "ascii", changes: changes)
    }
}
