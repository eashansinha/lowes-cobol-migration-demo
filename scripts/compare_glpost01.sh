#!/usr/bin/env bash
# compare_glpost01.sh - file parity for GLPOST01 (file in -> files out).
#
# Compares the run outputs in WORKDIR (default: work-glpost01/) against the
# golden outputs the COBOL job wrote for data/input/GLTRANS.dat:
#   data/expected/GLPOST01/GLPOSTED.dat   posted ledger      FB 120  key TRAN-ID
#   data/expected/GLPOST01/GLEXCEPT.dat   posting exceptions FB  80  key TRAN-ID
#   data/expected/GLPOST01/GLPOST01.rpt   batch control report      (text)
#
# Each fixed-width file goes through scripts/compare_files.py: bytes ->
# decoded fields -> keyed reconciliation -> control totals. Exit 0 only when
# every file is byte-identical, 8 otherwise.
#
# To prove a migrated implementation: point WORKDIR at the Java job's output
# directory (same input, same RUNDATE) - nothing else changes.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${1:-$ROOT/work-glpost01}"
GOLD="$ROOT/data/expected/GLPOST01"
RC=0

run() {                       # run <label> <compare_files args...>
    local label="$1"; shift
    echo "---- $label"
    "$ROOT/scripts/compare_files.py" "$@"
    local r=$?
    (( r > RC )) && RC=$r
    echo
}

echo "compare_glpost01.sh: work dir $WORKDIR"
for f in GLPOSTED.dat GLEXCEPT.dat GLPOST01.rpt; do
    if [[ ! -f "$WORKDIR/$f" ]]; then
        echo "  MISSING $WORKDIR/$f"
        RC=8
    fi
done
(( RC != 0 )) && { echo "compare_glpost01.sh: FAIL - output missing"; exit $RC; }

run "GLPOSTED posted ledger"   --layout "$ROOT/layouts/GLPOSTED.json" \
                               --baseline "$GOLD/GLPOSTED.dat" --target "$WORKDIR/GLPOSTED.dat"
run "GLEXCEPT exceptions"      --layout "$ROOT/layouts/GLEXCEPT.json" \
                               --baseline "$GOLD/GLEXCEPT.dat" --target "$WORKDIR/GLEXCEPT.dat"
run "GLRPT batch control report" --text \
                               --baseline "$GOLD/GLPOST01.rpt" --target "$WORKDIR/GLPOST01.rpt"

if (( RC == 0 )); then
    echo "compare_glpost01.sh: PASS - all three outputs byte-identical to golden"
else
    echo "compare_glpost01.sh: FAIL - see layers above; explain every difference before touching a golden"
fi
exit $RC
