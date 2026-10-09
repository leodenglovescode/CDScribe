#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build pinned standalone ARM64 helpers; never accesses optical drives."""
from pathlib import Path
import concurrent.futures, hashlib, json, os, shutil, subprocess, tarfile, urllib.request
import sys
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".dependencies"
MANIFEST = json.loads((ROOT / "Dependencies/manifest.json").read_text())
ENV = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
ENV.update(CFLAGS="-Os -arch arm64 -mmacosx-version-min=15.0", CXXFLAGS="-Os -arch arm64 -mmacosx-version-min=15.0", LDFLAGS="-arch arm64 -mmacosx-version-min=15.0")
JOBS = str(min(8, os.cpu_count() or 2))
PREFIX = CACHE / "prefix"
(CACHE / "sources").mkdir(parents=True, exist_ok=True)
(CACHE / "work").mkdir(parents=True, exist_ok=True)
(CACHE / "empty-pkgconfig").mkdir(exist_ok=True)
ENV["PKG_CONFIG_LIBDIR"] = str(CACHE / "empty-pkgconfig")
ENV["PKG_CONFIG_PATH"] = ""
def run(args, directory, log):
    subprocess.run(args, cwd=directory, env=ENV, stdout=log, stderr=subprocess.STDOUT, check=True)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
STAMP = CACHE / "build.json"
recipe_hash = digest(Path(__file__))
manifest_hash = digest(ROOT / "Dependencies/manifest.json")
def cached_build():
    if not STAMP.exists(): return False
    try:
        stamp = json.loads(STAMP.read_text())
        if stamp["recipe_sha256"] != recipe_hash or stamp["manifest_sha256"] != manifest_hash: return False
        return all(digest(PREFIX / "bin" / name) == value for name, value in stamp["helpers"].items()) and all(
            digest(CACHE / "sources" / package["archive"]) == package["sha256"] for package in MANIFEST)
    except (OSError, KeyError, ValueError): return False
if cached_build():
    print("Reusing checksum-verified bundled helpers.", flush=True)
    sys.exit(0)
def build(package):
    name, version = package["name"], package["version"]
    archive = CACHE / "sources" / package["archive"]
    if not archive.exists(): urllib.request.urlretrieve(package["url"], archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != package["sha256"]:
        raise RuntimeError(f"Source checksum mismatch for {name}; refusing to build")
    directory = CACHE / "work" / f"{name}-{version}"
    if not directory.exists():
        with tarfile.open(archive) as source: source.extractall(CACHE / "work", filter="data")
    print(f"Building {name} {version}", flush=True)
    with (CACHE / f"{name}-build.log").open("w") as log:
        args = ["./configure", "--prefix=/usr/local"]
        if name == "ffmpeg":
            args += ["--arch=aarch64", "--target-os=darwin", "--disable-autodetect", "--disable-everything", "--disable-shared", "--enable-static", "--enable-small", "--disable-network", "--disable-doc", "--disable-debug", "--disable-ffplay", "--enable-gpl", "--enable-version3", "--enable-zlib", "--enable-protocol=file,pipe", "--enable-demuxer=flac,wav,pcm_s16le,pcm_s32le,image2,png_pipe,jpeg_pipe", "--enable-muxer=flac,wav,pcm_s16be,pcm_s16le,pcm_s32le,image2", "--enable-decoder=flac,pcm_s16le,pcm_s32le,png,mjpeg,wrapped_avframe", "--enable-encoder=flac,pcm_s16le,pcm_s16be,pcm_s32le,png", "--enable-parser=flac,png,mjpeg", "--enable-filter=aresample,aformat,anull,color,format,scale", "--enable-indev=lavfi", "--extra-cflags=" + ENV["CFLAGS"], "--extra-ldflags=" + ENV["LDFLAGS"]]
        else:
            args += ["--without-lame", "--disable-rpath"]
        run(args, directory, log)
        run(["make", "-j" + JOBS], directory, log)
        if name == "ffmpeg":
            for tool in ["ffmpeg", "ffprobe"]:
                (PREFIX / "bin").mkdir(parents=True, exist_ok=True)
                shutil.copy2(directory / tool, PREFIX / "bin" / tool)
        else:
            (PREFIX / "bin").mkdir(parents=True, exist_ok=True)
            shutil.copy2(directory / "dao/cdrdao", PREFIX / "bin/cdrdao")
    print(f"Built {name}", flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(build, MANIFEST))
for tool in ["ffmpeg", "ffprobe", "cdrdao"]:
    binary = PREFIX / "bin" / tool
    subprocess.run(["strip", "-x", str(binary)], check=True)
    architecture = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip()
    if architecture != "arm64": raise RuntimeError(f"Unexpected architecture for {tool}: {architecture}")
    linkage = subprocess.check_output(["otool", "-L", str(binary)], text=True)
    for line in linkage.splitlines()[1:]:
        dependency = line.strip().split(" ")[0]
        if not (dependency.startswith("/usr/lib/") or dependency.startswith("/System/Library/")):
            raise RuntimeError(f"Non-system dependency remains in {tool}: {dependency}")
print("All three helpers link only to macOS system libraries.", flush=True)

STAMP.write_text(json.dumps({"recipe_sha256": recipe_hash, "manifest_sha256": manifest_hash,
    "helpers": {name: digest(PREFIX / "bin" / name) for name in ["ffmpeg", "ffprobe", "cdrdao"]}}, indent=2) + "\n")
