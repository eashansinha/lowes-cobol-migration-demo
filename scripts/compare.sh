#!/usr/bin/env bash
# compare.sh - golden-master verification for PRCUPD01.
#
# Compares the run outputs in WORKDIR (default: work/) byte-for-byte against
#   data/expected/PRCUPD01.rpt              audit / exception report
#   data/db2/expected_after/ITEM_PRICE.csv  DB2 ITEM_PRICE after-state
#   data/db2/expected_after/PRICE_HIST.csv  DB2 PRICE_HIST after-state
#
# Exit 0 when every file matches, 8 when any file differs or is missing.
# Use this same script to prove equivalence of a migrated implementation:
# point WORKDIR at the Java job's output directory.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${1:-$ROOT/work}"
RC=0

compare_one() {
    local label="$1" expected="$2" actual="$3"
    if [[ ! -f "$actual" ]]; then
        echo "  MISMATCH $label : output missing ($actual)"
        RC=8
        return
    fi
    if cmp -s "$expected" "$actual"; then
        echo "  MATCH    $label : $(wc -l < "$actual") lines identical"
    else
        echo "  MISMATCH $label"
        diff -u "$expected" "$actual" | head -40 | sed 's/^/           /'
        RC=8
    fi
}

echo "compare.sh: work dir $WORKDIR"
compare_one "PRCRPT report        " "$ROOT/data/expected/PRCUPD01.rpt"             "$WORKDIR/PRCUPD01.rpt"
compare_one "ITEM_PRICE after     " "$ROOT/data/db2/expected_after/ITEM_PRICE.csv" "$WORKDIR/ITEM_PRICE.csv"
compare_one "PRICE_HIST after     " "$ROOT/data/db2/expected_after/PRICE_HIST.csv" "$WORKDIR/PRICE_HIST.csv"

if (( RC == 0 )); then
    echo "compare.sh: PASS - all outputs match golden files"
else
    echo "compare.sh: FAIL - see mismatches above"
fi
exit $RC
