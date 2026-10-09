#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -project CDScribe.xcodeproj -scheme CDScribe -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p build
# ditto replaces matching bundle contents without touching other build files.
ditto build/DerivedData/Build/Products/Release/CDScribe.app build/CDScribe.app
codesign --force --sign - build/CDScribe.app
codesign --verify --deep --strict build/CDScribe.app
file build/CDScribe.app/Contents/MacOS/CDScribe
print "Built: $PWD/build/CDScribe.app"
