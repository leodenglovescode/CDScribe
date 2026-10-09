# CDScribe dependency notices

CDScribe's original Swift and Objective-C source is licensed GPL-3.0-or-later. The full GPL v3 text is in LICENSE. There is no analytics, account, advertising, subscription, or remote metadata service.

## FFmpeg and FFprobe

- Project: https://ffmpeg.org/
- Source: https://ffmpeg.org/download.html
- Role: FLAC metadata through FFprobe/libavformat; FLAC decoding and PCM conversion through FFmpeg/libavcodec/libswresample.
- License: FFmpeg is normally LGPL-2.1-or-later; enabled options can make an executable GPL-2.0-or-later or GPL-3.0-or-later. Inspect `ffmpeg -L` and `ffmpeg -version` for the executable used. The installed Homebrew 9.0.2 build has `--enable-gpl --enable-version3`; its GPL v3 license text supplied the identical standard text in LICENSE.
- The app discovers separately installed executables and invokes them via Process. FFmpeg, FFprobe, and their shared libraries are not included in the delivered .app. Redistribution with these dependencies must include the applicable licenses and satisfy corresponding-source obligations for the exact binary builds and all linked GPL components. Do not assume every FFmpeg build is redistributable; `--enable-nonfree` builds are not.
- Audio uses the native SW Resampler with an enlarged 128-tap filter in the tested environment. Builds advertising `--enable-libsoxr` use SoX resampling with precision 28. The latter branch has not been exercised in this environment.

## cdrdao

- Project and TOC documentation: https://cdrdao.sourceforge.net/
- Source: https://github.com/cdrdao/cdrdao
- License: GPL-2.0-or-later, as stated in the installed 1.2.6 COPYING notice. It runs as a separate optional executable and is not bundled or linked into CDScribe.
- Role: TOC parsing and complete image read validation; optional disc-at-once writing on compatible drives. No cdrdao implementation source was copied into CDScribe.

## Apple system frameworks and development tools

SwiftUI, AppKit, Foundation, DiscRecording and IOKit are system-provided Apple frameworks. They are not bundled as proprietary third-party libraries. Building requires the Apple SDK and agreement to Apple's Xcode/SDK licenses. The app is GPL-licensed; the macOS operating system and Apple's SDK are not open source. The portable core models and TOC generation are independent of the native UI; the current package's burn bridge is macOS-only.

## Swift

Swift is open source under Apache-2.0 with Runtime Library Exception: https://www.swift.org/LICENSE.txt. System Swift runtime libraries remain system dependencies.

## Artwork and icon

The application icon is original vector drawing code in Scripts/generate-icon.swift. Imported album artwork remains the user's own data and is neither shipped in the app nor embedded into CD-Text. Generated test fixtures contain original synthetic audio.
