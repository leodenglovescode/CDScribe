# CDScribe

**Your music, written right.**

A free native SwiftUI macOS app that reads tagged FLAC albums, maps their metadata into actual CD-Text, prepares continuous Red Book CD-DA audio, and writes through Apple's DiscRecording framework or an optional cdrdao backend.

**Current status: host-tested MVP; physical writing and on-disc readback remain unverified.** The included ARM64 app is a real compiled GUI. An attached Apple USB SuperDrive was detected and reports CD-Text and session-at-once support. It contained no ready disc, so no physical burn has been claimed.

## Install and launch

1. Install the free FFmpeg tools. With Homebrew: `brew install ffmpeg`. FFmpeg and FFprobe are required. `brew install cdrdao` enables additional TOC validation and the experimental cdrdao writer.
2. Open `build/CDScribe.app`. This local build is ad-hoc signed, not notarized. It runs on the development Mac with the installed tools. A downloaded copy may require approval in macOS Privacy & Security. Do not disable Gatekeeper system-wide.
3. CDScribe finds tools in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, or `Contents/Helpers`. Alternate executable paths can be configured in CDScribe → Settings.

The delivered bundle doesn't include external FFmpeg/cdrdao binaries. Normal importing and burning require no network connection. Files are read locally and never sent to a service.

## Use

1. Drag an album folder or FLAC files onto the window, or use File → Open FLAC Files (⌘O) / Open Album Folder (⇧⌘O). An import replaces the current review session.
2. Review automatically populated album title, performer, artwork, track titles, artists, durations and optional ISRCs. Tagged tracks sort numerically by TRACKNUMBER. Multi-disc albums appear as separate disc groups in the selector; they are never combined silently. Use the arrows to reorder selected tracks.
3. Open CD-Text Preview (⇧⌘P). Choose strict Latin-1 or ASCII. For names outside the selected encoding, explicitly choose transliteration and review all displayed changes, or correct the text. Unsupported text blocks preparation; no names are silently replaced.
4. Connect a compatible CD writer, insert a blank CD-R/CD-RW, and select the drive. CDScribe requires advertised CD-Text and session-at-once support. It checks actual media capacity again immediately before writing.
5. Keep **Gapless** selected for continuous albums, or select optional pauses. The first track always has the mandatory two-second pregap; no pause is inserted between other tracks by default.
6. Click **Burn Audio CD**. Conversion is automatic: FFmpeg decodes the FLACs to 44.1 kHz, 16-bit stereo PCM, the disc layout is validated, and then the real audio-CD burn begins. A conversion or validation failure stops the operation before writing. No separate preparation step is required. The optional **Disc → Prepare Audio Without Burning** menu action lets you convert and validate in advance for inspection/export; it never operates the laser. **Export Prepared Disc** saves the prepared audio and layout for inspection.
7. With verification selected, DiscRecording is asked to verify the audio; CDScribe separately reads and compares physical CD-Text through IOKit when available. Results explicitly distinguish completed writing from unverified audio or text. **Read CD-Text** displays actual disc text in Diagnostics independently of importing.

CD-Text does not contain artwork and does not control Music's or another player's online album recognition. Drive, player and encoding support vary. ISRC syntax is checked; a syntactically valid code is not proof of registration. CDScribe reads ISRC only from the embedded FLAC `ISRC` tag (or your edits in the review table). It uses no online ISRC lookup service, and missing codes remain empty. CDScribe never invents ISRCs. Semicolon-separated lists are treated as multiple values, not as a malformed single code. Equivalent duplicates collapse to one code. When several distinct values remain, the optional on-disc ISRC is omitted and clearly shown in the preview; the track ISRC menu lets you choose a supplied code without retyping. Original tags remain intact, and multiple values do not block audio or title/artist CD-Text preparation. Click a track’s Review indicator to read its warnings. **Choose ISRCs…** offers shared codes for tracks with the same choices, or applies each track’s own first/second/etc. tagged value in one action. You can omit or reset ISRC choices for the whole album. **ISRC Preview…** shows original tags, the exact on-disc code, local format checks, and repeated-code warnings. A code shared across different songs may indicate incorrect tags: ISRC identifies a recording, not an album. Checks do not prove registration or song identity; an optional link opens IFPI’s search website without uploading audio or automatically choosing matches.

Burn speeds come from the selected writer's current media status, not a preset list. The native bridge reads the media dictionary (with support for older top-level status layouts), translates Apple's CD media constants, and accounts for integer KB/s reporting when displaying nominal speed multipliers. It sends the exact reported KB/s rate to DiscRecording after rechecking it at burn time. Insert a blank CD-R to populate the menu. Only finite, positive, reported rates are offered; the lowest available rate is initially selected and there is no unrestricted Automatic/maximum option. Changing writers or media refreshes the choices. A stale rate is rejected again immediately before writing. If no speeds can be confirmed, burning is disabled. The experimental cdrdao backend requires a matching native drive identifier and offers only reported whole-number rates its command line can represent. The selected rate is a hardware request; actual write speed may vary during a burn.

## Audio and metadata behavior

- FFprobe/libavformat reads FLAC tags; a bounded FLAC metadata reader extracts exact STREAMINFO sample counts and embedded PICTURE blocks. It supports native `.flac` files, not Ogg FLAC or files prefixed with ID3 tags.
- Mapping: ALBUM → disc TITLE; ALBUMARTIST → disc PERFORMER; TITLE → track TITLE; ARTIST → track PERFORMER. Missing ALBUMARTIST falls back to a common track artist, or an explicitly shown Various Artists compilation label. Missing TITLE uses the filename. Missing ALBUM uses the folder name. Missing performer blocks writing until corrected.
- Mixed album titles or explicit album artists form separate groups. DISCNUMBER splits physical discs. Ambiguous duplicate track numbers receive a warning. Files without track numbers follow tagged files in natural filename order.
- 16-/24-bit FLAC at 44.1, 48, 88.2, 96 and 192 kHz is tested. Mono is duplicated into stereo; surround is rejected until explicitly downmixed outside the app.
- Every track is decoded to lossless signed 32-bit stereo PCM at its native rate. Consecutive tracks sharing a sample rate are concatenated before resampling, preserving filter state across their transitions. Mixed-rate runs use separate converters and are joined without inserted silence; their filter state cannot be continuous across differing rates.
- Tested resampling: SW Resampler, filter size 128, cutoff 0.97; triangular dither for resampling or reducing depth. Unchanged 16-bit/44.1 kHz material is transferred bit for bit with no dither. No normalization, ReplayGain, volume filter or loudness adjustment runs.
- The continuous disc image is signed 16-bit stereo, 44,100 Hz, big-endian for cdrdao. Native WAV slices are little-endian PCM of the same samples. CD sectors contain 588 stereo frames / 2,352 bytes, at 75 sectors per second.
- Track markers round to the nearest sector (at most half a sector of marker shift). Samples at a boundary remain in the continuous image; they are neither dropped nor padded. Only the final disc sector receives up to 587 zero frames. Optional pregaps are independent layout instructions.
- Red Book layout checks include 1–99 tracks, four-second minimum track lengths, exact image size, continuous offsets, pregaps, and 74-/80-minute or actual media capacity. There is no overburn, truncation, erasing or multisession support.
- Temporary preparation can require several GB for high-rate albums. Space is checked first. Prepared files are removed when you edit metadata/options or switch discs. Export them before exiting if you want to retain them. A crash may leave `CDScribe-*` directories in the system temporary folder.

## Build and test

Requires Apple Silicon, macOS 15 or later, Xcode with Swift 6 (tested with Xcode 27 on macOS 27.0.1), and the dependencies above. Earlier supported OS versions have not been runtime-tested. The main window explicitly presents on launch and uses a single-window scene.

```sh
# If the command-line tools rather than Xcode are selected:
sudo env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license

./Scripts/build.sh
./Scripts/test.sh
./Scripts/generate-demo.sh
open build/CDScribe.app
```

Open `CDScribe.xcodeproj` for the native application target. It uses the local Swift package product CDScribeCore; no remote package resolution is needed. Unit and integration tests live in the Swift package and run through `swift test` or its package test scheme in Xcode. `Scripts/generate-project.py` reproducibly regenerates the checked-in app project if app source files change. `Scripts/generate-icon.swift` produces original PNG icon artwork; the checked-in ICNS is already available.

Tests generate tagged synthetic FLAC files and cover metadata extraction, artwork, sorting, fallbacks, compilations, multi-disc albums, ISRCs, TOC escaping/Latin-1, unsupported Unicode, capacity, gapless layout, all requested sample rates, exact 16-bit PCM preservation, continuous resampling, literal process arguments and cancellation. Integration tests deliberately fail if FFmpeg, FFprobe or cdrdao is missing instead of reporting a skipped pipeline as passed. The mock burn service explicitly reports that no disc was written.

## Architecture

- CDScribeApp / MainView / AppModel — native SwiftUI review, options, preview, progress and commands.
- AlbumImportService / FLACHeader — local importing, libavformat metadata and bounded FLAC artwork reader.
- AlbumModel / TrackModel / MetadataMapper — editable in-memory tags and encoding policy.
- AudioConversionService / DiscLayout / TOCGenerator — decoding, continuous image, sector validation and CD-Text TOC.
- DiscDriveService / BurningService — backend abstraction and drive snapshots.
- NativeDisc — small Objective-C bridge to Apple's DRDevice, DRTrack, DRCDTextBlock and DRBurn, plus IOKit CD-Text readback.
- VerificationService / DiagnosticsView — independent readback comparisons, real backend output and errors.

The native app/bridge is macOS-specific. Models, mapping, TOC generation and process-based audio preparation are designed for later Windows/Linux reuse; they do not yet constitute a portable supported build.

## Troubleshooting

- **No writer:** check cables/power and Refresh; compare `system_profiler SPDiscBurningDataType`. Restricted development processes may be unable to see the writer even when the normally launched app can.
- **cdrdao scanbus access error:** cdrdao 1.2.6 initially returned `IOCreatePlugInInterfaceForService failed: -536870210` in the restricted development process. From an unrestricted user process, scanbus found the SuperDrive and drive-info confirmed CD-Text writing. Normal app use needs no administrator privileges. The optional cdrdao backend is conservative about parsing reported capabilities/media and may reject an unrecognized response. DiscRecording remains the default because it offers native media status and the integrated verification path.
- **Metadata encoding:** choose transliteration in the preview and review changes. DiscRecording's own character conversion and block-size check must agree before preparation succeeds.
- **Unsupported/missing dependencies:** inspect Diagnostics (⇧⌘D) and set full executable paths in Settings. Source filenames are passed as argument array values, never interpolated into shell commands.
- **Preparation fails:** inspect the exact error. Truncated FLACs, unknown sample counts, unsupported surround/sample rates, too-short tracks, insufficient temporary space and oversize albums block writing.
- **Verification unavailable or differs:** a completed burn does not imply readback success. Audio offset behavior and CD-Text reading depend on the drive. Keep the reported distinction, play the disc and test it on your intended CD-Text player.
- **Abort:** stopping preparation is safe for source files. Aborting an active write can waste a CD-R; a confirmation appears and native writing waits for terminal drive status. Quitting during a write should be avoided.
- **Xcode system component warnings:** this Mac's Xcode emitted outdated CoreDevice/CoreSimulator warnings during a macOS-only build. The macOS compiler and app build can still work; no iOS simulator is required.

See Documentation/VALIDATION.md for the precise validation record and remaining hardware test checklist.

## License and distribution

GPL-3.0-or-later. See LICENSE and THIRD_PARTY_NOTICES.md. Any distribution must meet corresponding-source and dependency licensing obligations. The provided build is local and ad-hoc signed; no repository, binary, release or website has been published. No paid or proprietary third-party dependency is added.
