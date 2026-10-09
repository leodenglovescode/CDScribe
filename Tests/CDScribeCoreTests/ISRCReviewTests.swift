// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import CDScribeCore

@Suite("Album ISRC review") struct ISRCReviewTests {
    func album(_ values: [String]) -> AlbumModel {
        AlbumModel(title: "Album", artist: "Artist", tracks: values.enumerated().map {
            TrackModel(source: URL(fileURLWithPath: "/tmp/\($0.offset).flac"), title: "Song \($0.offset + 1)", artist: "Artist", isrc: $0.element)
        })
    }
    @Test func sharedPairChosenOnceForElevenSongs() throws {
        let raw = "GBAYE0200770;GBAYE1600189"
        var a = album(Array(repeating: raw, count: 11))
        #expect(ISRCReview.commonCodes(a) == ["GBAYE0200770", "GBAYE1600189"])
        #expect(ISRCReview.apply(.suppliedCode("GBAYE1600189"), to: &a) == 11)
        #expect(a.tracks.allSatisfy { $0.isrc == raw })
        #expect(ISRCReview.rows(a).allSatisfy { $0.output == "GBAYE1600189" })
        #expect(ISRCReview.repeatedCodes(a, onDisc: true).first?.trackNumbers == Array(1...11))
        let text = try MetadataMapper.cdText(a, policy: .latin1)
        #expect(text.tracks.allSatisfy { $0.isrc == "GBAYE1600189" })
        #expect(text.changes.contains { $0.contains("On-disc ISRC") })
        #expect(ISRCReview.apply(.suppliedCode("GBAYE1600189"), to: &a) == 0)
    }
    @Test func positionalChoiceUsesEveryTracksOwnCode() {
        var a = album(["GBAYE0200770;GBAYE1600189", "GBAYE0200771;GBAYE1600190", "GBAYE0200772", "", "BROKEN;GBAYE1600191"])
        #expect(ISRCReview.commonCodes(a).isEmpty)
        #expect(ISRCReview.apply(.taggedValue(1), to: &a) == 3)
        #expect(ISRCReview.rows(a).map(\.output) == ["GBAYE1600189", "GBAYE1600190", "GBAYE0200772", "", "GBAYE1600191"])
        #expect(ISRCReview.repeatedCodes(a, onDisc: true).isEmpty)
        #expect(ISRCReview.rows(a)[4].malformedSourceValues == ["BROKEN"])
    }
    @Test func bulkCodeIsNeverAppliedToUnrelatedTrack() {
        var a = album(["GBAYE0200770;GBAYE1600189", "GBAYE0200771;GBAYE1600190", "GBAYE0200770"])
        #expect(ISRCReview.apply(.suppliedCode("GBAYE1600189"), to: &a) == 1)
        #expect(a.tracks[1].isrcSelection == nil)
        #expect(a.tracks[2].isrcSelection == nil)
        #expect(ISRCReview.apply(.suppliedCode("BROKEN"), to: &a) == 0)
        #expect(ISRCReview.apply(.taggedValue(-1), to: &a) == 0)
        #expect(ISRCReview.apply(.taggedValue(99), to: &a) == 0)
    }
    @Test func omitAndResetAreReversibleIncludingMalformedTags() throws {
        var a = album(["GBAYE0200770;GBAYE1600189", "BROKEN", "GBAYE0200771", ""])
        let originals = a.tracks.map(\.isrc)
        #expect(ISRCReview.apply(.omitAll, to: &a) == 4)
        #expect(ISRCReview.rows(a).allSatisfy { $0.output.isEmpty && $0.problem == nil })
        #expect(try MetadataMapper.cdText(a, policy: .latin1).tracks.allSatisfy { $0.isrc.isEmpty })
        #expect(ISRCReview.apply(.resetAll, to: &a) == 4)
        #expect(a.tracks.map(\.isrc) == originals)
        #expect(ISRCReview.rows(a)[1].problem != nil)
        #expect(ISRCReview.rows(a)[2].status == "Format valid · registration unchecked")
    }
    @Test func repeatedSourceCodesShownBeforeChoosingOutput() {
        let a = album(["GBAYE0200770;GBAYE1600189", "gb-aye-02-00770;GBAYE1600189"])
        #expect(ISRCReview.repeatedCodes(a, onDisc: false).count == 2)
        #expect(ISRCReview.repeatedCodes(a, onDisc: true).isEmpty)
        #expect(!ISRCReview.warnings(a).isEmpty)
        #expect(ISRCReview.availablePositions(a) == [0, 1])
    }
    @Test func duplicatesWithinOneTrackDoNotWarnAboutOtherRecordings() {
        let a = album(["GBAYE0200770;GBAYE0200770", "GBAYE0200771"])
        #expect(ISRCReview.warnings(a).isEmpty)
        #expect(ISRCReview.rows(a).allSatisfy { $0.problem == nil && !$0.output.isEmpty })
    }
}
