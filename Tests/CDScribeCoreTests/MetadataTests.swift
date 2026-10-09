// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import CDScribeCore

@Suite("Metadata and CD-Text") struct MetadataTests {
    func track(_ number: Int?, disc: Int = 1, name: String = "track.flac", artist: String = "Artist") -> TrackModel {
        TrackModel(source: URL(fileURLWithPath: "/tmp/\(name)"), title: "Song", artist: artist, album: "Album", trackNumber: number, discNumber: disc)
    }
    @Test func tagNumberFractions() { #expect(MetadataMapper.number("02/12") == 2); #expect(MetadataMapper.number("0") == nil); #expect(MetadataMapper.number("abc") == nil) }
    @Test func numericSorting() { #expect(MetadataMapper.sorted([track(10), track(2), track(1)]).map(\.trackNumber) == [1, 2, 10]) }
    @Test func discSorting() { #expect(MetadataMapper.sorted([track(1, disc: 2), track(2), track(1)]).map(\.discNumber) == [1, 1, 2]) }
    @Test func naturalFallbackOrder() { #expect(MetadataMapper.sorted([track(nil, name: "10.flac"), track(nil, name: "2.flac")]).first?.source.lastPathComponent == "2.flac") }
    @Test func isrcValidation() {
        #expect(MetadataMapper.validISRC("gb-ayE-73-00101") == "GBAYE7300101")
        for invalid in ["GBA123", "12ABC2300001", "GBABC2A00001", "GBABC23000010", ""] { #expect(MetadataMapper.validISRC(invalid) == nil) }
    }
    @Test func semicolonISRCsAreIndividualCodes() throws {
        let raw = "GBAYE0200770;GBAYE1600189"
        #expect(MetadataMapper.isrcValues(raw) == ["GBAYE0200770", "GBAYE1600189"])
        #expect(MetadataMapper.validISRC("GBAYE0200770") == "GBAYE0200770")
        #expect(MetadataMapper.validISRC("GBAYE1600189") == "GBAYE1600189")
        var t = track(1); t.isrc = raw
        #expect(t.isrcCandidates.count == 2)
        #expect(!t.metadataWarnings.contains { $0.contains("Invalid") })
        let text = try MetadataMapper.cdText(AlbumModel(title: "Album", artist: "Artist", tracks: [t]), policy: .latin1)
        #expect(text.tracks[0].isrc.isEmpty)
        #expect(text.tracks[0].title == "Song")
        #expect(text.changes.contains { $0.contains("No ISRC will be written") })
    }
    @Test func chooseSuppliedISRCWithoutChangingSourceTag() throws {
        var t = track(1); t.isrc = "GBAYE0200770;GBAYE1600189"
        t.isrcSelection = "GBAYE1600189"
        #expect(try MetadataMapper.discISRC(t) == "GBAYE1600189")
        #expect(t.isrc == "GBAYE0200770;GBAYE1600189")
        #expect(t.metadataWarnings.isEmpty)
        let album = AlbumModel(title: "Album", artist: "Artist", tracks: [t])
        let text = try MetadataMapper.cdText(album, policy: .latin1)
        let toc = try TOCGenerator.render(text: text, layout: AudioConversionService.estimatedLayout(album, gapSeconds: 0))
        #expect(toc.contains("ISRC \"GBAYE1600189\""))
        #expect(!toc.contains("GBAYE0200770"))
        t.isrc = "GBAYE0200770"
        #expect(t.isrcSelection == nil)
        #expect(try MetadataMapper.discISRC(t) == "GBAYE0200770")
    }
    @Test func repeatedEquivalentISRCsCollapseAndWhitespaceIsHandled() throws {
        var t = track(1); t.isrc = " ; gb-aye-02-00770 ; GBAYE0200770; \n"
        #expect(MetadataMapper.isrcValues(t.isrc) == ["GBAYE0200770"])
        #expect(try MetadataMapper.discISRC(t) == "GBAYE0200770")
        #expect(MetadataMapper.validISRC("ISRC GB-AYE-02-00770") == "GBAYE0200770")
        t.isrc = " ; \n"
        #expect(try MetadataMapper.discISRC(t).isEmpty)
    }
    @Test func malformedOrStaleISRCSelectionIsNeverWritten() throws {
        var t = track(1); t.isrc = "GBAYE0200770;BROKEN"
        #expect(try MetadataMapper.discISRC(t).isEmpty)
        t.isrcSelection = "GBAYE1600189"
        #expect(throws: (any Error).self) { try MetadataMapper.discISRC(t) }
        t.isrcSelection = ""
        #expect(try MetadataMapper.discISRC(t).isEmpty)
        t.isrc = "BROKEN"
        #expect(throws: (any Error).self) { try MetadataMapper.discISRC(t) }
        t.isrc = "GBAYE0200770"
        #expect(t.metadataWarnings.isEmpty)
    }
    @Test func automaticMapping() throws {
        let text = try MetadataMapper.cdText(AlbumModel(title: "Album", artist: "Album Artist", tracks: [track(1)]), policy: .latin1)
        #expect(text.title == "Album"); #expect(text.performer == "Album Artist")
        #expect(text.tracks[0].title == "Song"); #expect(text.tracks[0].performer == "Artist"); #expect(text.tracks[0].isrc.isEmpty)
    }
    @Test func missingTitleUsesFilename() throws {
        var track = track(1, name: "03 - Song.flac"); track.title = ""; track.artist = ""
        let text = try MetadataMapper.cdText(AlbumModel(title: "Album", artist: "Performer", tracks: [track]), policy: .latin1)
        #expect(text.tracks[0].title == "03 - Song"); #expect(text.tracks[0].performer == "Performer")
    }
    @Test func compilationPerformers() throws {
        let text = try MetadataMapper.cdText(AlbumModel(title: "Compilation", artist: "Various Artists", tracks: [track(1, artist: "First"), track(2, artist: "Second")]), policy: .latin1)
        #expect(text.performer == "Various Artists"); #expect(text.tracks.map(\.performer) == ["First", "Second"])
    }
    @Test func invalidIsrcBlocksBurn() {
        var t = track(1); t.isrc = "NOT-AN-ISRC"
        #expect(throws: (any Error).self) { try MetadataMapper.cdText(AlbumModel(title: "Album", artist: "Artist", tracks: [t]), policy: .latin1) }
    }
    @Test func latin1Accents() throws {
        let text = try MetadataMapper.cdText(AlbumModel(title: "Björk — Live", artist: "Artist", tracks: [track(1)]), policy: .transliterate)
        #expect(text.title == "Bjork - Live"); #expect(!text.changes.isEmpty)
        #expect(try MetadataMapper.cdText(AlbumModel(title: "Björk", artist: "Artist", tracks: [track(1)]), policy: .latin1).title == "Björk")
    }
    @Test func unsupportedUnicodeIsNotSilentlyLost() {
        #expect(throws: (any Error).self) { try MetadataMapper.cdText(AlbumModel(title: "音乐 🎵", artist: "Artist", tracks: [track(1)]), policy: .latin1) }
    }
    @Test func controlCharacterRejected() {
        #expect(throws: (any Error).self) { try MetadataMapper.cdText(AlbumModel(title: "Album\nTRACK AUDIO", artist: "Artist", tracks: [track(1)]), policy: .latin1) }
    }
    @Test func tocEscaping() { #expect(TOCGenerator.escape("A \"quote\" \\ slash") == "A \\\"quote\\\" \\\\ slash") }
    @Test func textSizeLimit() throws {
        var t = track(1); t.title = String(repeating: "Long track title ", count: 400)
        let text = try MetadataMapper.cdText(AlbumModel(title: "Album", artist: "Artist", tracks: [t]), policy: .latin1)
        #expect(throws: (any Error).self) { try NativeBurningService.validateText(text) }
    }
}

@Suite("CD-DA layout") struct LayoutTests {
    func album(_ count: Int = 2, frames: Int64 = 44100 * 5 + 17) -> AlbumModel {
        AlbumModel(title: "Album", artist: "Artist", tracks: (1...count).map { TrackModel(source: URL(fileURLWithPath: "/tmp/\($0).flac"), title: "Track \($0)", artist: "Artist", sampleFrames: frames) })
    }
    @Test func sectorConstants() { #expect(CDDA.sectors(forFrames: 588) == 1); #expect(CDDA.sectors(forFrames: 589) == 2); #expect(CDDA.msf(4501) == "01:00:01") }
    @Test func gaplessLayout() throws {
        let layout = AudioConversionService.estimatedLayout(album(), gapSeconds: 0)
        try layout.validate()
        #expect(layout.tracks[0].pregapSectors == 150); #expect(layout.tracks[1].pregapSectors == 0)
        #expect(layout.tracks[1].startSector == layout.tracks[0].sectors)
        #expect(layout.paddingFrames >= 0 && layout.paddingFrames < 588)
    }
    @Test func explicitGaps() {
        let layout = AudioConversionService.estimatedLayout(album(3), gapSeconds: 2)
        #expect(layout.tracks.map(\.pregapSectors) == [150, 150, 150])
    }
    @Test func capacities() {
        #expect(CDDA.capacity74 == 333000); #expect(CDDA.capacity80 == 360000)
        let layout = AudioConversionService.estimatedLayout(album(1, frames: 44100 * 75 * 60), gapSeconds: 0)
        #expect(throws: (any Error).self) { try layout.validate(capacity: CDDA.capacity74) }
        #expect(throws: Never.self) { try layout.validate(capacity: CDDA.capacity80) }
    }
    @Test func shortTracksAreRejected() {
        #expect(throws: (any Error).self) { try AudioConversionService.estimatedLayout(album(1, frames: 44100 * 3), gapSeconds: 0).validate() }
    }
    @Test func maxTrackCount() {
        #expect(throws: (any Error).self) { try AudioConversionService.estimatedLayout(album(100), gapSeconds: 0).validate() }
    }
    @Test func tocIsAudioAndText() throws {
        let a = album(); let text = try MetadataMapper.cdText(a, policy: .latin1)
        let toc = try TOCGenerator.render(text: text, layout: AudioConversionService.estimatedLayout(a, gapSeconds: 0))
        #expect(toc.hasPrefix("CD_DA")); #expect(toc.contains("TITLE \"Album\"")); #expect(toc.contains("PERFORMER \"Artist\""))
        #expect(toc.components(separatedBy: "TRACK AUDIO").count == 3); #expect(!toc.contains("MODE1"))
    }
    @Test func backendTextCapabilityRequiresPositiveConfirmation() {
        #expect(CdrdaoPreflight.supportsText("CD-TEXT writing is supported."))
        #expect(!CdrdaoPreflight.supportsText("CD-TEXT writing is not supported."))
        #expect(!CdrdaoPreflight.supportsText("No CD-TEXT information"))
    }
    @Test func backendRejectsNonblankAndUnknownMedia() throws {
        let sample = "Disk type: CD-R\nDisk status: empty\nTotal Capacity: 79:59:74 (359999 blocks)"
        #expect(try CdrdaoPreflight.blankCapacity(sample) == 359999)
        for invalid in [sample.replacingOccurrences(of: "empty", with: "complete"), "Disk type: CD-R\nNot empty: yes\nTotal Capacity: 79:59:74", sample.replacingOccurrences(of: "CD-R", with: "DVD-R"), sample.replacingOccurrences(of: "79:59:74", with: "79:99:99")] {
            #expect(throws: (any Error).self) { try CdrdaoPreflight.blankCapacity(invalid) }
        }
    }
    @Test func burnSpeedOptionsFollowReportedMedia() {
        #expect(BurnSpeedPolicy.available([16, 4, 8, 4, 0, -1, .infinity, .nan]) == [4, 8, 16])
        #expect(BurnSpeedPolicy.available([4, 4.5, 8], integerOnly: true) == [4, 8])
        #expect(BurnSpeedPolicy.label(4.5).contains("4.5"))
    }
    @Test func burnSpeedSelectionChangesWithWriterAndMedia() {
        #expect(BurnSpeedPolicy.selection(8, reported: [4, 8, 16]) == 8)
        #expect(BurnSpeedPolicy.selection(16, reported: [4, 8]) == 4)
        #expect(BurnSpeedPolicy.selection(8, reported: []) == 0)
    }
    @Test func burnSpeedRejectsUnknownAndUnrestrictedRates() throws {
        try BurnSpeedPolicy.validate(8, reported: [4, 8, 16])
        for invalid in [0.0, -1, 2, 32, Double.infinity, Double.nan] {
            #expect(throws: (any Error).self) { try BurnSpeedPolicy.validate(invalid, reported: [4, 8, 16]) }
        }
        #expect(throws: (any Error).self) { try BurnSpeedPolicy.validate(8, reported: []) }
        #expect(throws: (any Error).self) { try BurnSpeedPolicy.validate(4.5, reported: [4.5], integerOnly: true) }
    }

}
