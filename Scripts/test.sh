#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test
