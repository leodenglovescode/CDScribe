# Contributing to CDScribe

Use Swift 6 and native macOS controls. Keep metadata mapping, audio preparation, interface state and physical writing separate. Read source FLACs without modifying them. Never interpolate shell commands or add hidden volume processing.

On Apple Silicon with Xcode and Python 3.12+, run `./Scripts/test.sh` and `./Scripts/build.sh`. These build pinned, checksum-verified helpers; end users install nothing extra. `python3 Scripts/package-release.py` creates the self-contained app ZIP, corresponding dependency sources and SHA256SUMS. Helper source archives and build outputs are ignored by Git.

Generated integration fixtures contain original synthetic audio. Tests use the same compact helper build as the release, including metadata, artwork, all requested sample rates, exact 16-bit preservation and continuous resampling. Tests do not query or write a physical disc. Keep the automated Tests directory; do not check in test screenshots, private paths or generated albums.

For hardware changes, record drive model, media, speed, backend and actual result. Distinguish preparation, physical writing, player recognition, playback, audio readback and CD-Text readback. Do not run another instance or device probe while a burn is active. Never erase or write a user's disc without explicit authorization. See Documentation/VALIDATION.md.

The Xcode project references the local Swift package. Regenerate it with `python3 Scripts/generate-project.py` when adding/removing app sources. Tests run through Swift Package Manager; the Xcode app scheme has no test target. Package the release with the build script to include and sign all helpers.

Keep GPL-compatible dependencies and audit exact build options before redistribution. Release source assets must correspond to the shipped binaries. Never claim tests passed or hardware worked unless the relevant check actually ran.
