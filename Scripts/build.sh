#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 Scripts/build-dependencies.py
xcodebuild -project CDScribe.xcodeproj -scheme CDScribe -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
app="$PWD/build/Release/CDScribe.app"
mkdir -p build/Release
ditto build/DerivedData/Build/Products/Release/CDScribe.app "$app"
mkdir -p "$app/Contents/Helpers" "$app/Contents/Resources/Licenses/FFmpeg" "$app/Contents/Resources/Licenses/cdrdao"
for helper in ffmpeg ffprobe cdrdao; do
  cp ".dependencies/prefix/bin/$helper" "$app/Contents/Helpers/$helper"
  codesign --force --sign - "$app/Contents/Helpers/$helper"
done
cp LICENSE THIRD_PARTY_NOTICES.md Dependencies/manifest.json "$app/Contents/Resources/Licenses/"
cp .dependencies/work/ffmpeg-*/LICENSE.md .dependencies/work/ffmpeg-*/COPYING.* "$app/Contents/Resources/Licenses/FFmpeg/"
cp .dependencies/work/cdrdao-*/COPYING .dependencies/work/cdrdao-*/paranoia/README "$app/Contents/Resources/Licenses/cdrdao/"
python3 Scripts/write-dependency-notices.py "$app/Contents/Resources/Licenses/cdrdao"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
file "$app/Contents/MacOS/CDScribe" "$app/Contents/Helpers/"*
print "Built: $app"
