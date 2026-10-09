<p align="center">
  <img src="Documentation/Assets/icon.png" width="144" alt="CDScribe CD icon">
</p>

<h1 align="center">CDScribe</h1>
<p align="center"><em>Your music, written right.</em></p>
<p align="center">
  <a href="https://github.com/leodenglovescode/CDScribe/releases/latest">Download for Apple Silicon</a> ·
  <a href="LICENSE">GPL-3.0-or-later</a> ·
  <a href="Documentation/VALIDATION.md">Tested functionality</a>
</p>

CDScribe burns FLAC albums as standard audio CDs, with track titles and artists written as physical CD-Text. Drag an album in, review its automatically imported tags, insert a blank CD-R and burn.

A native SwiftUI app. Free, open source and offline. No accounts, subscriptions, ads or analytics. **Everything needed to import, convert and burn is included in the download.**

## Download and open

1. Download `CDScribe-v0.1.0-macos-arm64.zip` from [Releases](https://github.com/leodenglovescode/CDScribe/releases/latest).
2. Unzip it and move **CDScribe.app** to Applications.
3. Open CDScribe and connect a compatible USB CD writer.

Requires an Apple Silicon Mac and macOS 15 or later. This release was built and tested on macOS 27; earlier versions are not yet runtime-tested. It is ad-hoc signed and **not notarized**. If macOS blocks the download, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. You do not need to install Homebrew, FFmpeg or cdrdao.

## Make an audio CD

1. Drag in a folder or FLAC files, or use **File → Open FLAC Files / Open Album Folder**.
2. Review the album, track order and artwork. **CD-Text Preview** shows the titles and performers that will be written. Edits affect the disc only; original FLAC files stay unchanged.
3. Choose the writer, insert a blank CD-R and select a speed from the drive's reported options. Use **Gapless** for continuous albums, or set an optional track pause.
4. Click **Burn Audio CD**. CDScribe automatically converts the audio, checks the layout and capacity, and writes the disc. Progress and errors come from the actual tools.

This creates CD-DA audio: 44,100 Hz, signed 16-bit stereo PCM, readable by conventional audio CD players. FLAC files are decoded before writing. **Disc → Prepare Audio Without Burning** is an optional way to prepare and export the PCM/TOC in advance.

## Features

- Embedded album/album artist, track title/artist, track and disc numbers, ISRC candidates and artwork.
- Track-number sorting, editable metadata, track reordering, compilation and multi-disc grouping.
- Automatic disc and track CD-Text; title falls back to the filename and album artist falls back to track artists where appropriate.
- 16-bit and 24-bit FLAC at 44.1, 48, 88.2, 96 and 192 kHz. High-quality resampling and conditional dithering, with no volume normalization.
- Continuous resampling across tracks with matching sample rates; no inserted pauses by default. CD sector boundaries are accounted for, with padding only at the disc end.
- Real media detection, 74-/80-minute planning, capacity validation and drive-reported speed choices.
- cdrdao disc-at-once writing with CD-Text. Apple's APIs supply native drive status and optional physical CD-Text readback.
- Native light, dark and system appearance, keyboard shortcuts, accessibility labels and a Diagnostics panel.

### ISRC choices

ISRCs come from your files' embedded tags. CDScribe does not look them up online or invent them. Multiple values such as `GBAYE0200770;GBAYE1600189` are shown as separate choices. The ISRC preview offers a bulk choice when tracks share candidates, individual corrections, omission and checks for malformed or repeated codes.

The checker validates the code's **format**, not its ownership or recording identity. Identical ISRCs across different songs can indicate bad source tags; a bulk choice does not make them correct. Unresolved multiple choices are omitted rather than guessed. You can burn a normal audio CD without ISRCs.

### CD-Text and character support

CD-Text stores text, not album artwork. A compatible player must support CD-Text to display it. CD-Text also does not control online album recognition in Apple Music or other players.

The preview supports Latin-1, strict ASCII and an explicit ASCII transliteration option. Unsupported characters produce a warning/error before writing; CDScribe does not silently replace names. Review transliterated text before burning.

## Troubleshooting

- **Speed unavailable:** wait for the blank disc to become ready, then refresh. Speed choices come from the attached drive and media; CDScribe does not invent an unrestricted option.
- **Device already in use:** wait for another burn, rip or player session to finish. Close other disc applications before retrying. Never restart or probe a writer during an active burn.
- **Import or preparation failed:** open Diagnostics for the tool's actual error. A missing bundled helper means the app copy is incomplete; download the release again. Advanced executable overrides are optional.
- **Burn failed:** review Diagnostics before retrying. A partially written CD-R may be unusable. CDScribe never erases, forces an overburn or silently truncates tracks.
- **Names absent in a player:** check whether the player reads physical CD-Text. Online metadata and physical disc text are independent.

The Apple USB SuperDrive reported CD-Text support and speeds of 10×, 16× and 24× with the tested blank CD-R. A user completed a cdrdao burn and reported the resulting eleven-track Coldplay disc recognized in a second optical reader. The packaged helper build has not yet been used for a physical burn. Other drives, standalone-player playback, physical ISRC values and readback verification remain hardware-dependent. See [validation details](Documentation/VALIDATION.md).

**Verify CD-Text after burning** attempts physical text readback and reports success only when it matches the preview. Audio readback verification is not implemented for the cdrdao writer.

## Development

Use an Apple Silicon Mac, Xcode with its license accepted, and Python 3.12 or later. No third-party Swift packages or project generators are required.

```sh
./Scripts/test.sh
./Scripts/build.sh
python3 Scripts/package-release.py
```

The first development build downloads and verifies pinned official FFmpeg/cdrdao source archives, then builds small ARM64 executables. Subsequent builds reuse verified outputs. Downloads happen **during development**, never inside the released app. The integration suite uses those exact helper binaries and generated synthetic FLACs; it does not write or query a physical disc.

The finished app is `build/Release/CDScribe.app`; release files are in `dist/`. Open `CDScribe.xcodeproj` for UI development. Run the build script to produce the self-contained bundle. Regenerate the project with `python3 Scripts/generate-project.py` after adding or removing app source files. See [CONTRIBUTING.md](CONTRIBUTING.md).

| Component | Responsibility |
| --- | --- |
| `Sources/CDScribeApp` | SwiftUI interface, editing and operation state |
| `Sources/CDScribeCore` | Import, metadata mapping, PCM conversion, TOC layout and backend protocols |
| `Sources/NativeDisc` | DiscRecording/IOKit drive status, native validation and CD-Text readback |
| `Tests/CDScribeCoreTests` | Unit tests and real file-based integration tests |
| `Dependencies/manifest.json` | Exact upstream source versions and checksums |

Windows and Linux are future targets; this release is macOS only.

## License and bundled software

CDScribe's original code and icon are **GPL-3.0-or-later**. The app includes **FFmpeg/FFprobe 9.0.2**, built under GPL-3.0-or-later, and **cdrdao 1.2.6**, an independently executed GPL-2.0-or-later program. These do not require changing CDScribe's license. Apple system frameworks remain supplied by macOS.

[Third-party notices](THIRD_PARTY_NOTICES.md) describe the builds and licenses. Every release includes license texts inside the app and a **dependency-sources** archive containing the exact upstream source archives and build recipe. CDScribe's corresponding source is the release's tagged repository source. Sources are available without charge alongside the app; users do not need them to run it.
