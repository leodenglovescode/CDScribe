# CDScribe validation record

## Environment

Development and local runtime validation: macOS 27.0.1, Apple Silicon ARM64, Xcode 27 / Swift 6.4. The deployment target is macOS 15; earlier macOS versions and Windows/Linux have not been runtime-tested.

## Automated coverage

The unit and integration suites exercise actual tagged FLAC files, missing-tag fallbacks, compilations, multi-disc grouping, numeric ordering, ISRC syntax/multiple candidates/bulk choices, duplicate warnings, Unicode and TOC escaping, text encodings, capacities, exact sector/gap layout, real PCM conversion, embedded artwork and source-file preservation.

Audio tests cover 16-bit and 24-bit inputs at 44.1, 48, 88.2, 96 and 192 kHz. The 16-bit/44.1 kHz stereo path is compared byte-for-byte with source PCM. Continuous resampling across a track boundary is compared with one reference stream. TOCs are parsed and complete PCM images read by real cdrdao file-only commands. Native DiscRecording audio producers and text blocks validate without invoking a burn. A clearly labeled mock returns no physical write.

The release helpers are FFmpeg/FFprobe 9.0.2 and cdrdao 1.2.6 built from pinned original sources, with static internal libraries and only macOS system dynamic dependencies. The suite is run with CDSCRIBE_TEST_HELPERS set to the packaged helper directory, so it cannot accidentally test a separately installed Homebrew executable. The final self-contained ARM64 Release build succeeded; ad-hoc signatures verified with deep/strict checks. All 55 tests in five suites passed against the signed packaged helpers, including PNG and JPEG artwork import/preparation. The packaged ZIP is approximately 3.7 MB; dependency sources are provided as a separate optional archive. Archive relocation checks and source checksum verification are part of release validation.

## Hardware observations

- Apple USB SuperDrive discovery returned a real IOService device identifier. cdrdao reported CD-Text writing support; native APIs reported CD-Text and session-at-once support.
- With the user's blank CD-R inserted, native media information reported 359,844 free sectors and 1,764 / 2,822 / 4,233 KB/s rates, displayed as 10× / 16× / 24×. Nested media-speed lookup and media-type normalization were fixed and live-checked.
- An eleven-track native DiscRecording attempt failed while preparing with an unsupported pregap error. That writer is no longer exposed by the app; exact gap requirements were not relaxed or changed to hide the failure.
- A read-only cdrdao preflight confirmed blank media and reported 359,846 sectors; CDScribe conservatively uses the smaller native/media capacity. The selected speed must still appear in a fresh native status response.
- The user subsequently completed a cdrdao burn and supplied a screenshot of a second optical reader recognizing eleven tracks from Coldplay's *A Rush of Blood to the Head*, with correct displayed titles and artists. This is user-reported disc recognition. The screenshot does not independently establish raw physical CD-Text, ISRCs, audio readback or playback quality.

A separate development probe once encountered an already active user burn and cdrdao refused exclusive access. No successful probe was recorded for that run. CDScribe no longer performs a cdrdao bus scan automatically at startup; explicit Diagnostics refresh may scan when the app is idle. Development launch/probe hooks and generated captures have been removed from the shipping repository. No hardware access is needed for release packaging or automated tests.

## Remaining hardware and release limits

The newly bundled helper build has not yet written a physical disc. Standalone CD-player playback, audible gapless transitions, cancellation, other writers, physical ISRC values and CD-Text readback on finished media require further hardware tests. The app attempts CD-Text readback only when requested and reports failures honestly. Audio readback verification is not implemented for the cdrdao writer.

The release is ad-hoc signed, not Developer ID signed or notarized. Gatekeeper may require Open Anyway. No hardware success is inferred from compilation, mock results, media discovery or player metadata.
