<p align="center"><img src="Documentation/Assets/icon.png" width="112" alt="CDScribe CD icon"></p>
<h1 align="center">CDScribe</h1>
<p align="center"><em>Your music, written right.</em></p>

CDScribe is a free, native macOS app for burning FLAC albums as standard audio CDs with automatic CD-Text.

**Drag album → Review metadata → Insert CD-R → Burn.**

## Download

[Download for Apple Silicon](https://github.com/leodenglovescode/CDScribe/releases/latest) — approximately **3.7 MB**. Unzip and move **CDScribe.app** to Applications.

Everything is included. No dependency installation, first-run download, account, ads or analytics. Importing and burning work offline.

## Features

- Embedded metadata and artwork import, track-number sorting, multi-disc grouping and editable album/track information.
- CD-Text preview, track reordering and individual or bulk ISRC choices.
- Automatic conversion from 16-/24-bit FLAC to 44.1 kHz, 16-bit stereo CD-DA, with resampling and dithering. Original files and volume remain unchanged.
- Gapless audio, optional track pauses, capacity checks and burn speeds reported by the connected writer.
- cdrdao burning and optional physical CD-Text readback. Advance preparation/export is available under **Disc → Prepare Audio Without Burning**.

## Limitations

- **Apple Silicon, macOS 15+.** Runtime testing has been on macOS 27. Windows/Linux are not supported. A compatible CD-Text-capable writer is required.
- **Not notarized.** If macOS blocks the app, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway**.
- CD-Text display depends on the player. It contains no artwork and does not control online album recognition. Unsupported characters require correction or explicit transliteration.
- ISRC checks validate syntax, not recording identity. Ambiguous codes are omitted until selected.
- Audio readback verification is unavailable. CD-Text readback depends on hardware; physical burn testing of the bundled helper build is pending.

GPL-3.0-or-later. [Dependency licenses and corresponding sources](THIRD_PARTY_NOTICES.md) accompany releases. The source archive is optional. [Development instructions](CONTRIBUTING.md).
