#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Package the existing signed app and corresponding sources. No device access."""
from pathlib import Path
import hashlib, json, plistlib, shutil, subprocess, tarfile, tempfile
root = Path(__file__).resolve().parent.parent
app = root / "build/Release/CDScribe.app"
if not app.exists(): raise SystemExit("Run ./Scripts/build.sh first.")
with (app / "Contents/Info.plist").open("rb") as handle:
    version = plistlib.load(handle)["CFBundleShortVersionString"]
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
output = root / "dist"
output.mkdir(exist_ok=True)
zip_path = output / f"CDScribe-v{version}-macos-arm64.zip"
if zip_path.exists(): zip_path.unlink()
subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(zip_path)], check=True)
manifest = json.loads((root / "Dependencies/manifest.json").read_text())
source_path = output / f"CDScribe-v{version}-dependency-sources.tar.gz"
with tempfile.TemporaryDirectory(prefix="CDScribe-release-sources-") as temp:
    stage = Path(temp) / f"CDScribe-v{version}-dependency-sources"
    (stage / ".dependencies/sources").mkdir(parents=True)
    (stage / "Scripts").mkdir()
    (stage / "Dependencies").mkdir()
    for package in manifest:
        archive = root / ".dependencies/sources" / package["archive"]
        if hashlib.sha256(archive.read_bytes()).hexdigest() != package["sha256"]:
            raise SystemExit(f"Source checksum mismatch: {archive.name}")
        shutil.copy2(archive, stage / ".dependencies/sources" / archive.name)
    shutil.copy2(root / "Scripts/build-dependencies.py", stage / "Scripts/")
    shutil.copy2(root / "Dependencies/manifest.json", stage / "Dependencies/")
    shutil.copy2(root / "LICENSE", stage)
    shutil.copy2(root / "THIRD_PARTY_NOTICES.md", stage)
    (stage / "README.md").write_text(f"""# CDScribe {version} bundled-helper corresponding source

These are the exact unmodified official FFmpeg 9.0.2 and cdrdao 1.2.6 archives
used for the release helpers. Dependencies/manifest.json records upstream URLs
and SHA-256 checksums. Scripts/build-dependencies.py contains every configuration
flag. Source archives include all upstream copyright and license notices.

On Apple Silicon macOS, install Xcode with its license accepted and Python 3.12+
for development. From this directory run:

    python3 Scripts/build-dependencies.py

The script verifies local archives, extracts them and builds ARM64 helpers into
.dependencies/prefix/bin. No source download is needed because both archives
are included. Only macOS system libraries are linked dynamically. Compiled
bytes may differ with compiler/SDK/path versions; this is corresponding source,
not a claim of bit-for-bit reproducible builds.

CDScribe's own source and complete app packaging scripts are available at:
https://github.com/leodenglovescode/CDScribe/tree/v{version}
The release's GitHub Source code archives provide that tagged source too.

End users do not need this source archive to run CDScribe.
""")
    with tarfile.open(source_path, "w:gz") as tar:
        tar.add(stage, arcname=stage.name)
assets = [zip_path, source_path]
checksums = output / "SHA256SUMS"
checksums.write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in assets))
for path in assets + [checksums]: print(f"{path.name}: {path.stat().st_size:,} bytes")
