# CDScribe validation record

Date: **October 9, 2026 (Asia/Shanghai)**. Product name changed to **CDScribe** at the user's request before implementation. Everything is local; no remote repository or release was created.

## Environment

- macOS 27.0.1, build 26A434; ARM64.
- Xcode 27.0, build 27A266a; Swift 6.4. The default developer directory initially pointed at CommandLineTools; Xcode was selected per command using DEVELOPER_DIR. The user reviewed and accepted its license.
- FFmpeg / FFprobe 9.0.2 from Homebrew. FFmpeg has GPL/version3 options and **does not advertise libsoxr**. The tested conversion path uses the SW Resampler's 128-tap filter and conditional triangular dither. The optional libsoxr branch remains untested.
- cdrdao 1.2.6.
- Attached Apple USB SuperDrive. cdrdao identifies it as **HL-DT-ST DVDRW GX40N, firmware RQ00**. System Profiler separately labels it Apple SuperDrive, firmware 2.00. These are the actual outputs of those tools, not reconciled assumptions.

## Automated validation

**50 tests in five suites passed.** The integration suite uses real FFmpeg-generated FLACs and both cdrdao and DiscRecording validators. It does not operate the laser.

Coverage includes embedded FLAC metadata/artwork, fallback titles, natural/numeric sorting, compilation performers, separate multi-disc albums, ISRC validation, Latin-1, quotes/backslashes, rejecting unsupported Unicode/control characters, character transliteration, native CD-Text block capacity, 74-/80-minute capacity, the four-second track minimum, 99-track limit, gapless boundaries, configurable pregaps, all five requested source sample rates with 24-bit input, exact 16-bit/44.1 kHz PCM preservation, continuous 48 kHz resampling, malformed FLAC rejection, literal process arguments and cancellation, plus rejecting negative CD-Text capability and nonblank/unknown cdrdao media responses.

Burn-speed policy tests additionally cover duplicate/invalid reported rates, changes in writer or media speed lists, retaining valid choices, rejecting absent/unsupported/unrestricted speeds, and whole-number restrictions for cdrdao. The rebuilt ARM64 app requires an explicit reported rate, and the native writer rechecks the current media list immediately before starting. No speed negotiation with a ready blank disc or physical write was performed.

Multiple-ISRC regression tests use `GBAYE0200770;GBAYE1600189`, including a real tagged FLAC imported and prepared through both layout validators. Distinct codes remain in the source metadata, default to explicit omission of the optional on-disc ISRC, and can be chosen in the track menu. Tests cover normalized duplicates, printed prefixes, empty values, malformed/stale choices, correct selected TOC output and unchanged source bytes. The app was rebuilt with the picker and clickable Review warnings. Native GUI-model validation is recorded below; menu clicks have not been independently automated.

The strongest audio assertions compare actual samples:

- Two unaligned 16-bit tracks produce a continuous big-endian image exactly equal to their concatenated source PCM, followed only by zero padding in the final sector.
- Two 48 kHz tracks resampled as an album match a separately converted uninterrupted reference stream byte for byte.
- Prepared native WAVs report exactly 44,100 Hz, two channels and 16 bits via FFprobe. Native DRTrack producers report the expected sector lengths.
- cdrdao `toc-info`, `toc-size`, `show-toc`, and `read-test` accepted the generated layout; the block count matched the layout manifest.
- Source FLAC bytes before and after preparation matched.
- The mock burning service returned `physicalDiscWritten: false`.

Test output: [swift-tests.log](Evidence/swift-tests.log).

## Real compiled GUI

The checked-in **CDScribe.xcodeproj Release scheme built successfully** for ARM64. The app bundle is ad-hoc signed and `codesign --verify --deep --strict` passes. It is not notarized. Its Mach-O executable links to system frameworks; FFmpeg and cdrdao remain external installed tools.

The normally launched Release app was exercised through its real GUI model with a generated three-track FLAC album:

- Correct album, artist and all three track titles populated without manual entry.
- Prepared **661,500 audio sample frames** and **1,275 total sectors**, including the first track's required pregap.
- One real visible main window and a visible CD-Text preview sheet were observed programmatically in the delivered app at its final project path.
- Native and cdrdao discovery both found the attached SuperDrive.
- Main-window light-mode rendering was inspected. System dark-mode rendering was also inspected earlier in the test sequence. The in-app preview-sheet capture returned transparent compositor content, and an external window capture was unavailable; the preview's text/layout is therefore not claimed as independently verified by screenshot.

Evidence: [GUI report](Evidence/gui-smoke.json), [main window in light mode](Evidence/main-window-light.png), [delivered main window in dark mode](Evidence/main-window-dark.png). The report explicitly states `physicalDiscWritten: false`. The smoke-test launch option never invokes a burn backend.

GUI testing discovered and fixed native drive flags boxed as numeric JSON values instead of booleans. It also exposed a false over-capacity indicator when no media was inserted; the indicator now uses the selected planning capacity until the drive reports actual media capacity.

## Actual hardware probes

The initial restricted command process returned `IOCreatePlugInInterfaceForService failed: -536870210` and could not enumerate the drive. An unrestricted **ordinary user** process and the normally launched app could access it. Administrator privileges are not requested by the application.

- `cdrdao scanbus`: succeeded and returned the SuperDrive's exact IOService identifier.
- `cdrdao drive-info`: succeeded; reported **“CD-TEXT writing is supported.”**, selected Generic SCSI-3/MMC with options 0x0010, reported about 4,234 kB/s maximum writing speed, and BurnProof/JustLink support.
- DiscRecording: one Apple SuperDrive; **CD-Text true**, **CD session-at-once true**; no inserted media, no advertised media burn speeds, no free-media capacity.
- `cdrdao disk-info`: retried “Unit not ready” and exited 1 because there was no ready disc.
- No cdrdao write/simulate, DRBurn write, media erase or readback operation was performed.

These initial checks establish discovery and reported capabilities only. The later read-only check with inserted CD-R media is recorded below. Physical writing, playable audio, CD-Text on disc, burn cancellation and verification/read offsets remain unverified.

## Remaining physical test

A disposable blank CD-R and explicit authorization to use it are required for the generated test-tone disc. There was no ready disc during initial implementation. The user subsequently inserted a CD-R for speed diagnostics; those checks were read-only. No successful physical burn is reported.

1. Insert a disposable blank CD-R; confirm reported type, capacity, supported speeds and ready state.
2. Run the same album-preparation validations from the app and confirm the displayed CD-Text.
3. Burn through DiscRecording; capture actual engine progress, final status and any errors. Separately test cdrdao if desired. Never infer native write simulation safety from DRBurnTestingKey: Apple's documentation warns that unsupported simulation can become a real write, so CDScribe does not expose that mode.
4. Confirm audio verification actually ran and completed, or report it unavailable. Independently read physical CD-Text and compare all titles/performers with the preview.
5. Play the disc on the intended CD player and a second reader. Test a real continuous album for audible transitions, preferably with known CD-sector-aligned source boundaries.
6. Test any non-ASCII Latin-1 names, valid ISRC support, full-length albums and real 74-/80-minute media.
7. Validate native abort behavior using suitable disposable media; never count an abort request alone as proof the drive has stopped.

## Other limits

The optional cdrdao media-response parser and write path are implemented but remain untested with a ready disc. The native verification path also remains hardware-unverified and explicitly reports any unavailable or mismatched readback. Earlier macOS versions, other drives, surround input, Apple notarization and Windows/Linux builds are not validated. The current cdrdao path performs CD-Text readback where the native identifier is available; it does not claim audio readback verification.

Xcode emitted stale CoreDevice/CoreSimulator component warnings, but the macOS-only app builds succeeded. The computer-use tool's Node runtime was unavailable; GUI validation used a launch-only in-app test hook instead. The hook imports actual fixtures, prepares actual audio and captures only the app's own views.

The final launch check also exposed a macOS scene presentation failure. CDScribe now uses an explicit main-window scene, presents it on launch, and has a native AppKit window fallback hosting the same SwiftUI view/model. A real final-folder launch then passed GUI import/preparation and showed the main window and preview. The minimum supported deployment target is macOS 15; runtime validation remains on macOS 27. Protected Desktop-folder fixtures required a privacy prompt, so the final automatic GUI run used temporary-folder fixtures. Normal file selection grants user-chosen access through NSOpenPanel. Quit requests now retain the app while preparation or native burning is active, and release prepared temporary files on normal exit.


## Album-wide ISRC choices and checker

The updated ARM64 app built and its ad-hoc signature verified. Six additional tests cover one bulk choice for an eleven-song album sharing two codes, each track's own positional value, preserving unrelated tracks, reversible omission/reset, source/output duplicate detection and malformed-source reporting. The local checker reports format validity, not registration or recording identity. No automatic online lookup is implemented; the optional IFPI link is opened only by the user.

A separate instance of the delivered app imported eleven real synthetic FLACs carrying `GBAYE0200770;GBAYE1600189`. Its actual GUI model applied the shared second code once, regenerated and validated the selected audio/CD-Text layout, opened the ISRC review sheet, and reported one visible main window. The selected TOC contains eleven `GBAYE1600189` ISRC entries and zero entries for the other code. All original FLAC SHA-256 hashes matched after the test. The main window was visually inspected; native sheet image caching still loses composited control content, so the sheet's presentation and backing data were checked programmatically rather than claiming complete visual coverage. No disc was written.

Evidence: [GUI-model report](Evidence/isrc-review-gui-smoke.json), [main-window capture](Evidence/isrc-review-main-window.png), [tests](Evidence/swift-tests.log), [build](Evidence/xcode-release-build.log).


## Inserted CD-R speed diagnosis and fix

The user's attached Apple SuperDrive was queried with a blank CD-R inserted. Its media dictionary contained `DRDeviceBurnSpeedsKey: [1764, 2822, 4233]` KB/s, `DRDeviceMediaTypeCDR`, 359,844 free sectors, zero used blocks and zero recorded tracks. The original bridge incorrectly read speeds from the outer dictionary and passed Apple's internal media-type constant into a Swift readiness check expecting `CD-R`.

The bridge now reads nested media speeds (retaining support for older top-level layouts), translates CD media constants, and accounts for integer KB/s reporting within one KB/s when displaying nominal multipliers. It uses the exact original reported rate for the native burn request and rejects any selection absent from the current list. Four new tests cover the observed response, exact request rates, empty/malformed status, top-level compatibility, unsupported rates and media readiness. The missing-speed help text now distinguishes an absent disc from a present blank disc without a speed response.

A separate instance of the rebuilt app confirmed the actual inserted media as ready with speeds **10x, 16x, 24x** and selected **10x**. The GUI model's burn readiness was false before import and true after preparing a five-second synthetic FLAC. The main window was visually inspected and displayed `CD-R · Blank · 79:57` and `10x`. This test did not call the physical writing service. The test instance was closed separately from user instances.

Evidence: [live-media GUI report](Evidence/media-speed-gui-smoke.json), [main-window capture](Evidence/media-speed-main-window.png), [tests](Evidence/swift-tests.log), [ARM64 build](Evidence/xcode-release-build.log). Burn-speed discovery is now tested with inserted media; physical writing and actual speed negotiation during a burn remain unverified.


## Automatic conversion workflow clarification

Source inspection confirms that the Burn Audio CD action awaits `prepareIfNeeded()` before invoking either physical burning backend. Preparation generates and validates 44.1 kHz, signed 16-bit stereo PCM and a CD-DA layout; failures stop before the write call. Only prepared WAV audio tracks or the prepared PCM/TOC image reach the writers. Cached valid preparation can be reused, and metadata/layout edits invalidate it.

The redundant Prepare Audio button was removed from the main window. The remaining main action is Burn Audio CD, accompanied by explicit automatic-conversion copy and an accessibility hint. Optional advance preparation remains under Disc → Prepare Audio Without Burning for inspection/export. The ARM64 app rebuilt successfully and its ad-hoc signature verified. This change affects UI wording/placement only; the previously passing 50-test suite was not repeated. No physical burn was performed.
