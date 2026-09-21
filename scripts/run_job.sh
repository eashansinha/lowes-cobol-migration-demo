#!/usr/bin/env bash
# run_job.sh - local emulation of jcl/PRCUPD01.jcl
#
#   STEP010 SORT    sort the promo feed on SKU / EFF-DATE / PROMO-ID
#   STEP020 PRCUPD  run PRCUPD01 (DD names -> environment variables)
#   STEP030 COMPARE golden-master compare (scripts/compare.sh)
#
# Usage: scripts/run_job.sh [--no-compare] [--rundate YYYYMMDD] [--out DIR]
#
# Exit code mirrors the job's highest step return code:
#   0 clean, 4 warnings (skips / exceptions on the report), 8+ failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNDATE="20260921"
OUT="$ROOT/work"
DO_COMPARE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-compare) DO_COMPARE=0 ;;
        --rundate)    RUNDATE="$2"; shift ;;
        --out)        OUT="$2"; shift ;;
        *) echo "run_job.sh: unknown argument $1" >&2; exit 12 ;;
    esac
    shift
done

DATA="$ROOT/data"
BIN="$ROOT/bin/PRCUPD01"
JOB_RC=0

step_banner() { printf '\n==== %-8s %-8s %s\n' "PRCUPD01" "$1" "$2"; }

if [[ ! -x "$BIN" ]]; then
    echo "run_job.sh: $BIN not found - run scripts/build.sh first" >&2
    exit 12
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# ------------------------------------------------------------------ STEP010
step_banner STEP010 "SORT promo feed (SKU 11-18, EFF-DATE 27-34, PROMO-ID 1-10)"
LC_ALL=C sort -k1.11,1.18 -k1.27,1.34 -k1.1,1.10 \
    "$DATA/input/PROMOFEED.dat" > "$OUT/PROMOFEED.sorted.dat"
RC=$?
echo "STEP010 RC=$RC ($(wc -l < "$OUT/PROMOFEED.sorted.dat") records)"
(( RC > JOB_RC )) && JOB_RC=$RC
if (( RC > 4 )); then echo "JOB ABENDED IN STEP010"; exit $JOB_RC; fi

# ------------------------------------------------------------------ STEP020
step_banner STEP020 "PRCUPD01 nightly promo price update  RUNDATE=$RUNDATE"
printf 'RUNDATE=%s\n' "$RUNDATE" > "$OUT/SYSIN.txt"

# DD statements -> GnuCOBOL file assignment via environment variables
export DD_SYSIN="$OUT/SYSIN.txt"
export DD_PROMOIN="$OUT/PROMOFEED.sorted.dat"
export DD_ITEMMAST="$DATA/input/ITEMMAST.dat"
export DD_STORERGN="$DATA/input/STORE_REGION.csv"
export DD_ITMPRCI="$DATA/db2/before/ITEM_PRICE.csv"
export DD_ITMPRCO="$OUT/ITEM_PRICE.csv"
export DD_PRCHSTI="$DATA/db2/before/PRICE_HIST.csv"
export DD_PRCHSTO="$OUT/PRICE_HIST.csv"
export DD_PRCRPT="$OUT/PRCUPD01.rpt"

"$BIN"
RC=$?
echo "STEP020 RC=$RC"
(( RC > JOB_RC )) && JOB_RC=$RC
if (( RC > 4 )); then echo "JOB ABENDED IN STEP020"; exit $JOB_RC; fi

echo "  PRCRPT  -> $OUT/PRCUPD01.rpt  ($(wc -l < "$OUT/PRCUPD01.rpt") lines)"
echo "  ITMPRCO -> $OUT/ITEM_PRICE.csv"
echo "  PRCHSTO -> $OUT/PRICE_HIST.csv"

# ------------------------------------------------------------------ STEP030
if (( DO_COMPARE )); then
    step_banner STEP030 "COMPARE outputs against golden files"
    "$ROOT/scripts/compare.sh" "$OUT"
    RC=$?
    echo "STEP030 RC=$RC"
    (( RC > JOB_RC )) && JOB_RC=$RC
fi

echo
echo "PRCUPD01 JOB ENDED  MAXCC=$JOB_RC"
exit $JOB_RC
