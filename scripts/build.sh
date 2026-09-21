#!/usr/bin/env bash
# build.sh - compile the batch load modules with GnuCOBOL.
#
# Mainframe equivalent: the IGYWCL compile/link PROC producing
#   PRC.PROD.LOADLIB(PRCUPD01) with PRCRGN01 statically linked
#   GL.PROD.LOADLIB(GLPOST01)
#
# Usage: scripts/build.sh            -> bin/PRCUPD01 bin/GLPOST01
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/cobol/src"
CPY="$ROOT/cobol/copybooks"
BIN="$ROOT/bin"

if ! command -v cobc >/dev/null 2>&1; then
    echo "build.sh: cobc (GnuCOBOL) not found. Install with: sudo apt-get install -y gnucobol" >&2
    exit 1
fi

mkdir -p "$BIN"
echo "build.sh: $(cobc --version | head -1)"
echo "build.sh: compiling PRCUPD01 + PRCRGN01 -> $BIN/PRCUPD01"

# -x      : build an executable (main program first)
# -Wall   : all warnings (AUTHOR paragraph is flagged obsolete; that is expected in legacy code)
# -I      : copybook library (SYSLIB)
cobc -x -Wall -I "$CPY" \
     -o "$BIN/PRCUPD01" \
     "$SRC/PRCUPD01.cbl" "$SRC/PRCRGN01.cbl"

echo "build.sh: compiling GLPOST01 -> $BIN/GLPOST01"
cobc -x -Wall -I "$CPY" \
     -o "$BIN/GLPOST01" \
     "$SRC/GLPOST01.cbl"

echo "build.sh: OK"
