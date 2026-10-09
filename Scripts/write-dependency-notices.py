#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Retain the upstream license headers for cdrdao's vendored runtime code."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parent.parent
source = root / ".dependencies/work/cdrdao-1.2.6"
destination = Path(sys.argv[1])
headers = []
for relative in ["trackdb/DLexerBase.cpp", "paranoia/cdda_paranoia.h", "dao/main.cc"]:
    text = (source / relative).read_text()
    end = text.index("*/") + 2
    headers.append(relative + "\n" + text[:end])
(destination / "UPSTREAM-NOTICES.txt").write_text("\n\n".join(headers) + "\n")
