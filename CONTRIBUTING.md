# Contributing to CDScribe

Use Swift 6, native macOS controls and GPL-compatible dependencies. Keep source files read-only. Keep metadata mapping, image preparation, GUI state and physical writing separate. Avoid shell command interpolation and hidden audio processing.

Run `./Scripts/test.sh` with FFmpeg, FFprobe and cdrdao installed, then `./Scripts/build.sh`. Generated integration fixtures contain original synthetic audio. Report actual backend exits and distinguish a mock validation, a complete host pipeline, a physical write, audio readback and CD-Text readback.

For hardware changes, record the drive model/firmware, connection, media, speed, backend and actual results. Never use a user's existing disc for destructive experiments. Do not erase, overburn, normalize audio or publish a binary without explicit scope. The initial hardware checklist is in Documentation/VALIDATION.md.

The checked-in Xcode project uses the local Swift package. Regenerate it with `python3 Scripts/generate-project.py` when adding/removing app source files. Tests currently run through the Swift package, not the app target's empty test action.
