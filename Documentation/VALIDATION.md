# Development validation

The ARM64 Release build and deep/strict ad-hoc signature checks pass. The automated suite has 55 tests in five suites and passes against the signed helpers inside the app. GitHub Actions also builds the helpers and app from source and runs the suite on a clean macOS runner.

Coverage includes real FLAC metadata, missing-tag fallbacks, ordering, compilations, multi-disc grouping, ISRC choices, text encodings, TOC escaping, capacities, gap layouts, PNG/JPEG artwork and source preservation. Audio checks cover 16-/24-bit inputs at 44.1, 48, 88.2, 96 and 192 kHz, exact 16-bit PCM preservation and continuous resampling. cdrdao parses TOCs and reads prepared images without accessing a physical drive. Mock results are explicitly marked as non-physical.

The app ZIP passes relocation and signature checks. All helpers are ARM64 and dynamically depend only on macOS system libraries. Included upstream source archives match the checksums in Dependencies/manifest.json.

Hardware checks recorded Apple USB SuperDrive CD-Text support, blank CD-R capacity of 359,844 sectors and supported speeds of 10×, 16× and 24×. A cdrdao-written eleven-track album was recognized in a second optical reader. Disc recognition does not independently verify physical CD-Text, ISRCs or audio quality. The bundled helper build still requires physical burn testing; remaining product limitations are listed in README.md.

Tests and release packaging never query or write an optical disc. Hardware tests require dedicated media, and no device probes should run during an active burn.
