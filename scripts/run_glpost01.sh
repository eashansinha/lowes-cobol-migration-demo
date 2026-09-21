#!/usr/bin/env bash
# run_glpost01.sh - local emulation of jcl/GLPOST01.jcl (file in -> files out)
#
#   STEP010 SORT    sort the journal feed on BATCH-ID / ACCT-NO / TRAN-ID
#   STEP020 GLPOST  run GLPOST01 (DD names -> environment variables)
#   STEP030 COMPARE file parity against data/expected/GLPOST01/
#
# Usage: scripts/run_glpost01.sh [--no-compare] [--rundate YYYYMMDD]
#                                [--out DIR] [--trans FILE] [--acct FILE]
#
# Exit code mirrors the job's highest step return code:
#   0 clean, 4 exceptions / out-of-balance batch, 8+ failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNDATE="20260921"
OUT="$ROOT/work-glpost01"
TRANS="$ROOT/data/input/GLTRANS.dat"
ACCT="$ROOT/data/input/ACCTMAST.dat"
DO_COMPARE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-compare) DO_COMPARE=0 ;;
        --rundate)    RUNDATE="$2"; shift ;;
        --out)        OUT="$2"; shift ;;
        --trans)      TRANS="$2"; shift ;;
        --acct)       ACCT="$2"; shift ;;
        *) echo "run_glpost01.sh: unknown argument $1" >&2; exit 12 ;;
    esac
    shift
done

BIN="$ROOT/bin/GLPOST01"
JOB_RC=0

step_banner() { printf '\n==== %-8s %-8s %s\n' "GLPOST01" "$1" "$2"; }

if [[ ! -x "$BIN" ]]; then
    echo "run_glpost01.sh: $BIN not found - run scripts/build.sh first" >&2
    exit 12
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# ------------------------------------------------------------------ STEP010
step_banner STEP010 "SORT journal feed (BATCH-ID 56-63, ACCT-NO 19-28, TRAN-ID 1-10)"
LC_ALL=C sort -k1.56,1.63 -k1.19,1.28 -k1.1,1.10 "$TRANS" > "$OUT/GLTRANS.sorted.dat"
RC=$?
echo "STEP010 RC=$RC ($(wc -l < "$OUT/GLTRANS.sorted.dat") records)"
(( RC > JOB_RC )) && JOB_RC=$RC
if (( RC > 4 )); then echo "JOB ABENDED IN STEP010"; exit $JOB_RC; fi

# ------------------------------------------------------------------ STEP020
step_banner STEP020 "GLPOST01 daily GL posting  RUNDATE=$RUNDATE"
printf 'RUNDATE=%s\n' "$RUNDATE" > "$OUT/SYSIN.txt"

# DD statements -> GnuCOBOL file assignment via environment variables.
# COB_LS_FIXED=1 keeps every record at its LRECL (RECFM=FB semantics)
# instead of trimming trailing spaces, so the outputs are true fixed-width.
export COB_LS_FIXED=1
export DD_SYSIN="$OUT/SYSIN.txt"
export DD_GLTRANS="$OUT/GLTRANS.sorted.dat"
export DD_ACCTMAST="$ACCT"
export DD_GLPOSTED="$OUT/GLPOSTED.dat"
export DD_GLEXCEPT="$OUT/GLEXCEPT.dat"
export DD_GLRPT="$OUT/GLPOST01.rpt"

"$BIN"
RC=$?
echo "STEP020 RC=$RC"
(( RC > JOB_RC )) && JOB_RC=$RC
if (( RC > 4 )); then echo "JOB ABENDED IN STEP020"; exit $JOB_RC; fi

echo "  GLPOSTED -> $OUT/GLPOSTED.dat  ($(wc -l < "$OUT/GLPOSTED.dat") records, LRECL 120)"
echo "  GLEXCEPT -> $OUT/GLEXCEPT.dat  ($(wc -l < "$OUT/GLEXCEPT.dat") records, LRECL 80)"
echo "  GLRPT    -> $OUT/GLPOST01.rpt  ($(wc -l < "$OUT/GLPOST01.rpt") lines)"

# ------------------------------------------------------------------ STEP030
if (( DO_COMPARE )); then
    step_banner STEP030 "FILE PARITY against data/expected/GLPOST01"
    "$ROOT/scripts/compare_glpost01.sh" "$OUT"
    RC=$?
    echo "STEP030 RC=$RC"
    (( RC > JOB_RC )) && JOB_RC=$RC
fi

echo
echo "GLPOST01 JOB ENDED  MAXCC=$JOB_RC"
exit $JOB_RC
