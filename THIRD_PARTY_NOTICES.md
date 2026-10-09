# CDScribe third-party notices

CDScribe's original Swift, Objective-C, build scripts and icon drawing are GPL-3.0-or-later. See LICENSE for the complete GPL v3 text. Imported artwork and music remain user data and are not distributed with CDScribe.

## Bundled executable programs

These programs run through Foundation Process with argument arrays; their implementation is not copied into or linked with CDScribe's application binary. Static linking below refers to each helper's own internal libraries.

| Program | Version | Distribution license | Use |
| --- | --- | --- | --- |
| FFmpeg / FFprobe | 9.0.2 | GPL-3.0-or-later (`--enable-gpl --enable-version3`, no `--enable-nonfree`) | FLAC metadata, decoding, audio conversion and validation |
| cdrdao | 1.2.6 | GPL-2.0-or-later; bundled upstream components retain their notices | TOC validation and disc-at-once audio/CD-Text writing |

FFmpeg is copyright its contributors; https://ffmpeg.org/ and https://ffmpeg.org/legal.html. Its upstream LICENSE.md describes LGPL, GPL and permissively licensed portions. The exact build includes GPL v3 license texts and uses the built-in SW Resampler with a 128-tap filter, conditional triangular dithering and no normalization. No Homebrew libraries, SoX resampler, external codecs or network protocols are bundled. FLAC, PCM, the image support needed for artwork fixtures, resampling and local file/pipe I/O are enabled.

cdrdao is copyright Andreas Mueller and other contributors; https://github.com/cdrdao/cdrdao and https://cdrdao.sourceforge.net/. Its GPL-2.0-or-later grant appears in the source headers (for example dao/main.cc); COPYING supplies the full GPL v2 text. Its distributed source also includes Monty's paranoia extraction code with its GPL notices and generated PCCTS parser/runtime code with original permissive notices. Those remain separate upstream components of the cdrdao executable; they are not relicensed as CDScribe code. The build disables optional MP3/Vorbis/audio-playback libraries, which CDScribe does not use. Built-in optical-drive drivers and DAO/CD-Text writing are retained.

The three helpers are ARM64, built with macOS 15 deployment targets, and dynamically depend only on macOS system libraries. Checksums and official archive URLs are in Dependencies/manifest.json. Scripts/build-dependencies.py is the complete configuration/build recipe. Upstream sources are unmodified; configuration choices are recorded in that script.

## Corresponding source and redistribution

The GitHub release provides `CDScribe-v<VERSION>-dependency-sources.tar.gz` alongside the application ZIP. It contains the exact original FFmpeg and cdrdao archives, their checksums, the build script and build instructions. The tagged repository supplies CDScribe's own complete source and packaging scripts. License texts and this notice are also inside `CDScribe.app/Contents/Resources/Licenses`.

Redistributors must retain notices and provide corresponding source for the exact binaries they distribute under their applicable GPL terms. Running or aggregating these separate programs does not require replacing CDScribe's GPL-3.0-or-later license. If a redistributor links other code or enables additional components, they must audit that different build independently.

## macOS and Swift

SwiftUI, AppKit, Foundation, DiscRecording, IOKit and the system C/C++/zlib/Swift runtimes are supplied by macOS, not shipped as copied proprietary frameworks. Development requires agreement to Apple's Xcode/SDK terms. GPL system-library provisions apply to these system dependencies; CDScribe's GPL license does not relicense macOS.

Swift is available under Apache-2.0 with Runtime Library Exception: https://www.swift.org/LICENSE.txt. GitHub Actions checkout/setup-python/upload-artifact use MIT licenses and are development infrastructure, not bundled runtime dependencies. No TagLib, external Swift package, paid dependency or online metadata service is used.
