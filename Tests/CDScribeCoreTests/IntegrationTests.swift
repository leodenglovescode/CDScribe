// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AppKit
import Testing
import NativeDisc
@testable import CDScribeCore

struct Fixtures: Sendable {
    let directory: URL
    let tools: BackendTools
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CDScribeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let helpers = ProcessInfo.processInfo.environment["CDSCRIBE_TEST_HELPERS"] {
            let base = URL(fileURLWithPath: helpers, isDirectory: true)
            for name in ["ffmpeg", "ffprobe", "cdrdao"] {
                guard FileManager.default.isExecutableFile(atPath: base.appendingPathComponent(name).path) else {
                    throw CDScribeError.message("Required packaged helper is missing: \(name)")
                }
            }
            tools = BackendTools(ffmpeg: base.appendingPathComponent("ffmpeg"), ffprobe: base.appendingPathComponent("ffprobe"), cdrdao: base.appendingPathComponent("cdrdao"))
        } else {
            tools = BackendTools()
        }
        guard tools.ffmpeg != nil, tools.ffprobe != nil, tools.cdrdao != nil else { throw CDScribeError.message("Integration tests require ffmpeg, ffprobe and cdrdao. Install these dependencies before testing.") }
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func generate(_ name: String, rate: Int = 44100, frames: Int = 44100 * 5 + 17, bits: Int = 16, channels: Int = 2, metadata: [String: String], offset: Int = 0, artwork: URL? = nil) async throws -> (URL, Data) {
        let source = directory.appendingPathComponent(name + ".pcm"), output = directory.appendingPathComponent(name + ".flac")
        var bytes = Data(); bytes.reserveCapacity(frames * channels * (bits == 16 ? 2 : 4))
        for frame in 0..<frames {
            for channel in 0..<channels {
                let value = (frame + offset + channel * 7) % 4096 - 2048
                if bits == 16 { var sample = Int16(value).littleEndian; withUnsafeBytes(of: &sample) { bytes.append(contentsOf: $0) } }
                else { var sample = Int32(value * 65536 + ((frame + offset) % 128) * 256).littleEndian; withUnsafeBytes(of: &sample) { bytes.append(contentsOf: $0) } }
            }
        }
        try bytes.write(to: source)
        var args = ["-nostdin", "-v", "error", "-y", "-f", bits == 16 ? "s16le" : "s32le", "-ar", String(rate), "-ac", String(channels), "-i", source.path]
        if let artwork { args += ["-i", artwork.path, "-map", "0:a", "-map", "1:v", "-c:v", "copy", "-disposition:v", "attached_pic", "-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)"] }
        args += ["-c:a", "flac", "-sample_fmt", bits == 16 ? "s16" : "s32"]
        for key in metadata.keys.sorted() { args += ["-metadata", "\(key)=\(metadata[key]!)"] }
        args += [output.path]
        _ = try await ProcessRunner().checked(tools.ffmpeg!, args)
        return (output, bytes)
    }
    static func bigEndian(_ little: Data) -> Data {
        var big = little
        big.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in stride(from: 0, to: bytes.count, by: 2) { let temp = bytes[i]; bytes[i] = bytes[i+1]; bytes[i+1] = temp }
        }; return big
    }
}

@Suite("Real FLAC / FFmpeg / cdrdao / DiscRecording integration", .serialized)
struct IntegrationTests {
    @Test func taggedFLACToAudioDisc() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        let frameCount = 44100 * 5 + 17
        let (second, secondPCM) = try await fixture.generate("01 filename but second", frames: frameCount, metadata: ["TITLE": "Second", "ARTIST": "Second Artist", "ALBUM": "Compilation", "ALBUMARTIST": "Various Artists", "TRACKNUMBER": "2/2", "ISRC": "GBAYE7300101"], offset: frameCount)
        let (first, firstPCM) = try await fixture.generate("02 filename but first 音乐 ' quote", frames: frameCount, metadata: ["TITLE": "First \"quoted\" \\ title", "ARTIST": "Björk", "ALBUM": "Compilation", "ALBUMARTIST": "Various Artists", "TRACKNUMBER": "1/2"])
        let originalFirst = try Data(contentsOf: first), originalSecond = try Data(contentsOf: second)
        let imported = try await AlbumImportService(tools: fixture.tools).importURLs([fixture.directory])
        #expect(imported.count == 1); let album = try #require(imported.first)
        #expect(album.artist == "Various Artists"); #expect(album.tracks.map(\.trackNumber) == [1, 2])
        #expect(album.tracks[0].source == first); #expect(album.tracks[0].title == "First \"quoted\" \\ title")
        #expect(album.tracks[0].artist == "Björk"); #expect(album.tracks[0].sampleFrames == frameCount)
        let text = try MetadataMapper.cdText(album, policy: .latin1)
        let prepared = try await AudioConversionService(tools: fixture.tools).prepare(album, text: text); defer { prepared.remove() }
        let audio = try Data(contentsOf: prepared.audioURL)
        let expected = Fixtures.bigEndian(firstPCM + secondPCM)
        #expect(audio.prefix(expected.count) == expected)
        #expect(audio.dropFirst(expected.count).allSatisfy { $0 == 0 })
        #expect(audio.count % 2352 == 0); #expect(prepared.layout.paddingFrames < 588)
        #expect(prepared.layout.tracks[1].pregapSectors == 0)
        let toc = try String(contentsOf: prepared.tocURL, encoding: .isoLatin1)
        #expect(toc.contains("Björk")); #expect(toc.contains("ISRC \"GBAYE7300101\"")); #expect(toc.contains("First \\\"quoted\\\" \\\\ title"))
        let show = try await ProcessRunner().checked(fixture.tools.cdrdao!, ["show-toc", "disc.toc"], directory: prepared.directory)
        #expect(String(decoding: show.output, as: UTF8.self).contains("TRACK  1  Mode AUDIO"))
        let size = try await ProcessRunner().checked(fixture.tools.cdrdao!, ["toc-size", "disc.toc"], directory: prepared.directory)
        #expect(Int64(String(decoding: size.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) == prepared.layout.totalSectors)
        for wav in prepared.wavURLs {
            let probe = try await ProcessRunner().checked(fixture.tools.ffprobe!, ["-v", "error", "-show_streams", "-of", "json", wav.path])
            let root = try JSONSerialization.jsonObject(with: probe.output) as! [String: Any]
            let stream = (root["streams"] as! [[String: Any]])[0]
            #expect(stream["sample_rate"] as? String == "44100"); #expect(stream["channels"] as? Int == 2); #expect(stream["bits_per_sample"] as? Int == 16)
        }
        let mock = await MockBurningService()
        let result = try await mock.burn(prepared, options: BurnOptions(driveID: "MOCK"), progress: nil)
        #expect(!result.physicalDiscWritten)
        #expect(try Data(contentsOf: first) == originalFirst); #expect(try Data(contentsOf: second) == originalSecond)
    }
    @Test func nativePreparationValidatesActualPregaps() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        for i in 1...2 { _ = try await fixture.generate("Gap \(i)", metadata: ["TITLE": "Track \(i)", "ARTIST": "Artist", "ALBUM": "Gaps", "TRACKNUMBER": String(i)]) }
        let album = try #require(try await AlbumImportService(tools: fixture.tools).importURLs([fixture.directory]).first)
        let text = try MetadataMapper.cdText(album, policy: .latin1)
        for pause in [0, 2] {
            let disc = try await AudioConversionService(tools: fixture.tools).prepare(album, text: text, gapSeconds: pause)
            defer { disc.remove() }
            #expect(disc.layout.tracks.map(\.pregapSectors) == [150, Int64(pause * 75)])
            let paths = disc.wavURLs.map(\.path), sectors = disc.layout.tracks.map { NSNumber(value: $0.sectors) }
            try CDNativeDisc.validateAudioPaths(paths, sectors: sectors, gaps: disc.layout.tracks.map { NSNumber(value: $0.pregapSectors) })
            for invalid: [NSNumber] in [[150], [0, 0], [150, -1], [150, 2251], [150, 0.5]] {
                #expect(throws: (any Error).self) { try CDNativeDisc.validateAudioPaths(paths, sectors: sectors, gaps: invalid) }
            }
        }
    }
    @Test func semicolonTaggedFLACImportsAndPreparesWithoutInvalidISRC() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        let raw = "GBAYE0200770;GBAYE1600189"
        let (url, _) = try await fixture.generate("Multiple ISRC", metadata: ["TITLE": "Song", "ARTIST": "Artist", "ALBUM": "Album", "TRACKNUMBER": "1", "ISRC": raw])
        let original = try Data(contentsOf: url)
        var album = try #require(try await AlbumImportService(tools: fixture.tools).importURLs([url]).first)
        #expect(album.tracks[0].isrc == raw)
        #expect(album.tracks[0].isrcCandidates == ["GBAYE0200770", "GBAYE1600189"])
        #expect(!album.tracks[0].metadataWarnings.contains { $0.contains("Invalid") })
        let omitted = try MetadataMapper.cdText(album, policy: .latin1)
        #expect(omitted.tracks[0].isrc.isEmpty)
        let prepared = try await AudioConversionService(tools: fixture.tools).prepare(album, text: omitted)
        defer { prepared.remove() }
        #expect(!String(decoding: try Data(contentsOf: prepared.directory.appendingPathComponent("disc.toc")), as: UTF8.self).contains("ISRC"))
        album.tracks[0].isrcSelection = "GBAYE1600189"
        let selected = try MetadataMapper.cdText(album, policy: .latin1)
        #expect(selected.tracks[0].isrc == "GBAYE1600189")
        _ = try NativeBurningService.validateText(selected)
        #expect(try Data(contentsOf: url) == original)
    }
    @Test func missingTagsAndMultipleDiscs() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        _ = try await fixture.generate("10 Missing title", metadata: ["ARTIST": "Artist", "ALBUM": "Album", "TRACKNUMBER": "2", "DISCNUMBER": "1/2"])
        _ = try await fixture.generate("02 Tagged", metadata: ["TITLE": "Tagged", "ARTIST": "Artist", "ALBUM": "Album", "TRACKNUMBER": "1", "DISCNUMBER": "1/2"])
        _ = try await fixture.generate("03 Disc Two", metadata: ["TITLE": "Disc Two", "ARTIST": "Artist", "ALBUM": "Album", "TRACKNUMBER": "1", "DISCNUMBER": "2/2"])
        let albums = try await AlbumImportService(tools: fixture.tools).importURLs([fixture.directory])
        #expect(albums.count == 2); #expect(albums.map(\.discNumber) == [1, 2]); #expect(albums[0].artist == "Artist")
        #expect(albums[0].tracks.map(\.title) == ["Tagged", "10 Missing title"])
    }
    @Test func compilationWithoutAlbumArtist() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        _ = try await fixture.generate("1", metadata: ["TITLE": "One", "ARTIST": "A", "ALBUM": "Mix", "TRACKNUMBER": "1"])
        _ = try await fixture.generate("2", metadata: ["TITLE": "Two", "ARTIST": "B", "ALBUM": "Mix", "TRACKNUMBER": "2"])
        let albums = try await AlbumImportService(tools: fixture.tools).importURLs([fixture.directory])
        #expect(albums.count == 1); #expect(albums[0].artist == "Various Artists"); #expect(albums[0].tracks.map(\.artist) == ["A", "B"])
    }
    @Test func allRequestedSampleRatesAnd24BitPCM() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        var urls: [URL] = []
        for (i, rate) in [44100, 48000, 88200, 96000, 192000].enumerated() {
            let (url, _) = try await fixture.generate("rate-\(rate)", rate: rate, frames: rate * 5 + 13, bits: 24, metadata: ["TITLE": "Rate \(rate)", "ARTIST": "Artist", "ALBUM": "Rates", "TRACKNUMBER": String(i+1)])
            urls.append(url)
        }
        let album = try #require(try await AlbumImportService(tools: fixture.tools).importURLs(urls).first)
        #expect(album.tracks.map(\.sampleRate) == [44100, 48000, 88200, 96000, 192000]); #expect(album.tracks.allSatisfy { $0.bitsPerSample == 24 })
        let disc = try await AudioConversionService(tools: fixture.tools).prepare(album, text: MetadataMapper.cdText(album, policy: .latin1)); defer { disc.remove() }
        #expect(abs(Double(disc.layout.audioFrames) / 44100 - album.duration) < 0.001)
        #expect(disc.layout.tracks.count == 5); #expect(disc.layout.tracks.dropFirst().allSatisfy { $0.pregapSectors == 0 })
    }
    @Test func resamplingAcrossTrackBoundaryMatchesOneStream() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        let frames = 48000 * 5 + 19
        let (a, aPCM) = try await fixture.generate("a", rate: 48000, frames: frames, metadata: ["TITLE": "A", "ARTIST": "Artist", "ALBUM": "Continuous", "TRACKNUMBER": "1"])
        let (b, bPCM) = try await fixture.generate("b", rate: 48000, frames: frames, metadata: ["TITLE": "B", "ARTIST": "Artist", "ALBUM": "Continuous", "TRACKNUMBER": "2"], offset: frames)
        let album = try #require(try await AlbumImportService(tools: fixture.tools).importURLs([a, b]).first)
        let disc = try await AudioConversionService(tools: fixture.tools).prepare(album, text: MetadataMapper.cdText(album, policy: .latin1)); defer { disc.remove() }
        let source = fixture.directory.appendingPathComponent("reference.pcm"), reference = fixture.directory.appendingPathComponent("reference.cdr")
        try (aPCM + bPCM).write(to: source)
        let version = try await ProcessRunner().checked(fixture.tools.ffmpeg!, ["-version"])
        let soxr = String(decoding: version.output, as: UTF8.self).contains("--enable-libsoxr")
        let filter = soxr ? "aresample=44100:resampler=soxr:precision=28:osf=s16:dither_method=triangular" : "aresample=44100:resampler=swr:filter_size=128:phase_shift=10:cutoff=0.97:osf=s16:dither_method=triangular"
        _ = try await ProcessRunner().checked(fixture.tools.ffmpeg!, ["-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", "48000", "-ac", "2", "-i", source.path, "-af", filter, "-f", "s16be", reference.path])
        let expected = try Data(contentsOf: reference)
        #expect(try Data(contentsOf: disc.audioURL).prefix(expected.count) == expected)
    }
    @Test @MainActor func embeddedArtwork() async throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        let image = fixture.directory.appendingPathComponent("cover.png")
        _ = try await ProcessRunner().checked(fixture.tools.ffmpeg!, ["-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=32x32", "-frames:v", "1", image.path])
        let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: image)))
        let jpeg = fixture.directory.appendingPathComponent("cover.jpg")
        try #require(bitmap.representation(using: .jpeg, properties: [:])).write(to: jpeg)
        for cover in [image, jpeg] {
            let (url, _) = try await fixture.generate("Art-" + cover.pathExtension, metadata: ["TITLE": "Art", "ARTIST": "Artist", "ALBUM": "Artwork", "TRACKNUMBER": "1"], artwork: cover)
            let album = try #require(try await AlbumImportService(tools: fixture.tools).importURLs([url]).first)
            #expect(album.artwork == (try Data(contentsOf: cover)))
            let prepared = try await AudioConversionService(tools: fixture.tools).prepare(album, text: MetadataMapper.cdText(album, policy: .latin1))
            prepared.remove()
        }
    }
    @Test func malformedFLACRejected() throws {
        let fixture = try Fixtures(); defer { fixture.remove() }
        let broken = fixture.directory.appendingPathComponent("broken.flac")
        try Data([102, 76, 97, 67, 128, 0, 0, 34, 0]).write(to: broken)
        #expect(throws: (any Error).self) { try FLACHeader.read(broken) }
    }
    @Test func processArgumentsAreLiteral() async throws {
        let marker = "$(touch /tmp/CDScribe-should-not-exist); `echo unsafe` \\\""
        let result = try await ProcessRunner().checked(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", marker])
        #expect(String(decoding: result.output, as: UTF8.self) == marker)
        #expect(!FileManager.default.fileExists(atPath: "/tmp/CDScribe-should-not-exist"))
    }
    @Test func processCancellation() async throws {
        let task = Task { try await ProcessRunner().run(URL(fileURLWithPath: "/bin/sleep"), ["30"]) }
        try await Task.sleep(for: .milliseconds(150)); task.cancel()
        do { _ = try await task.value; Issue.record("The process did not cancel") }
        catch is CancellationError { } catch { Issue.record("Wrong cancellation error: \(error)") }
    }
}
