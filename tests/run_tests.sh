#!/usr/bin/env bash
# run_tests.sh - regression harness for the PRCUPD01 batch job.
#
# Builds the load module, runs the job end to end and asserts on the
# golden-master compare plus a handful of business-rule spot checks that
# make the intent of the sample data explicit. Exit 0 = all tests passed.
#
# Usage: tests/run_tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/work"
TMP="$ROOT/work-tests"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; }

assert_eq() {            # assert_eq <name> <expected> <actual>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
assert_grep() {          # assert_grep <name> <file> <regex>
    if grep -Eq -- "$3" "$2"; then ok "$1"; else bad "$1" "pattern not found: $3"; fi
}
assert_no_grep() {       # assert_no_grep <name> <file> <regex>
    if grep -Eq -- "$3" "$2"; then bad "$1" "unexpected match: $3"; else ok "$1"; fi
}
total() {                # total <label>  -> value from RUN TOTALS block
    grep -E "^ +$1 +[0-9]+$" "$WORK/PRCUPD01.rpt" | awk '{print $NF}'
}

echo "== T01 build"
if "$ROOT/scripts/build.sh" > "$ROOT/work-build.log" 2>&1; then
    ok "cobc build of PRCUPD01 + PRCRGN01"
else
    bad "cobc build failed" "$(tail -5 "$ROOT/work-build.log")"
    echo; echo "$PASS passed, $FAIL failed"; exit 1
fi

echo "== T02 end-to-end job run + golden-master compare"
"$ROOT/scripts/run_job.sh" > "$ROOT/work-run.log" 2>&1
RC=$?
assert_eq "job MAXCC is 4 (warnings: skips/rejects on the report)" "4" "$RC"
assert_grep "compare.sh reports PASS" "$ROOT/work-run.log" 'compare.sh: PASS'
assert_grep "STEP030 compare RC=0" "$ROOT/work-run.log" 'STEP030 RC=0'

echo "== T03 run totals"
assert_eq "promo records read"          "20" "$(total 'PROMO RECORDS READ')"
assert_eq "promos expired (phase 1)"    "2"  "$(total 'PROMOS EXPIRED \(PHASE 1\)')"
assert_eq "prices updated"              "30" "$(total 'PRICES UPDATED')"
assert_eq "prices raised to floor"      "9"  "$(total 'OF WHICH RAISED TO FLOOR')"
assert_eq "region overrides"            "6"  "$(total 'OF WHICH REGION OVERRIDE')"
assert_eq "prices unchanged"            "1"  "$(total 'PRICES UNCHANGED')"
assert_eq "promos skipped"              "4"  "$(total 'PROMOS SKIPPED \(WARNING\)')"
assert_eq "promos rejected"             "5"  "$(total 'PROMOS REJECTED \(EXCEPTION\)')"
assert_eq "price_hist rows inserted"    "32" "$(total 'PRICE_HIST ROWS INSERTED')"

echo "== T04 business-rule spot checks (report)"
RPT="$WORK/PRCUPD01.rpt"
assert_grep "BR-P1 percent off, .x9 round-down (149.00 -20% -> 119.19)"      "$RPT" '^PRM2026120 10004410 NE  P +149\.00 +149\.00 +119\.19  PROMO +UPDATED'
assert_grep "BR-P2 fixed price rounds down to .x9 (199.00 -> 198.99)"         "$RPT" '^PRM2026138 10033120 NE  F +249\.00 +249\.00 +198\.99  PROMO +UPDATED'
assert_grep "BR-P3 BOGO priced as REG/2 then floored+rounded up (9.98 -> 6.39)" "$RPT" '^PRM2026122 10041555 NE  B +9\.98 +9\.98 +6\.39  FLOOR +UPDATED'
assert_grep "BR-R1 NC BOGO suppressed (NOBOGO skip)"                          "$RPT" '^PRM2026122 10041555 NC  B .*NOBOGO  SKIP +REGION RULE NOBOGO'
assert_grep "BR-R2 NC freight uplift 8% (119.20 -> 128.69)"                   "$RPT" '^PRM2026120 10004410 NC  P +149\.00 +149\.00 +128\.69  RGNOVR NCFRT   UPDATED'
assert_grep "BR-R3 WC lumber cap 15% (4.28 -30% -> 3.59)"                     "$RPT" '^PRM2026121 10012233 WC  P +4\.28 +4\.28 +3\.59  RGNOVR WCLUM   UPDATED'
assert_grep "BR-P5 margin floor, rounded UP to .x9 (164.00 -35% -> 129.89)"   "$RPT" '^PRM2026133 10150022 NE  P +164\.00 +164\.00 +129\.89  FLOOR +UPDATED'
assert_grep "BR-E1 expired promo reverted to regular price"                   "$RPT" '^PRM2026081 10057890 NE  - +99\.99 +79\.99 +99\.99  EXPIRE +EXPIRED  PROMO END DATE PASSED'
assert_grep "BR-T1 store-level promo resolved to region (0417 -> SE)"         "$RPT" '^PRM2026125 10057890 SE  P +99\.99 +99\.99 +74\.99  PROMO +UPDATED'
assert_grep "BR-V2 unknown SKU rejected"                                      "$RPT" '^PRM2026128 99999999 .*REJECT   SKU NOT ON ITEM MASTER'
assert_grep "BR-V3 discontinued item rejected"                                "$RPT" '^PRM2026127 10115566 .*REJECT   ITEM DISCONTINUED'
assert_grep "BR-V4 future promo skipped"                                      "$RPT" '^PRM2026130 10078812 .*SKIP     NOT YET EFFECTIVE'
assert_grep "BR-V5 lapsed promo skipped"                                      "$RPT" '^PRM2026131 10061234 .*SKIP     PROMO ALREADY ENDED'
assert_grep "BR-U2 promo already in effect -> NOCHG"                          "$RPT" '^PRM2026112 10020977 MW  P .*NOCHG    PROMO ALREADY IN EFFECT'
assert_grep "BR-U1 missing ITEM_PRICE row rejected"                           "$RPT" '^PRM2026132 10199001 NC  P .*REJECT   NO ITEM_PRICE ROW FOR REGION'

# Documented CURRENT behaviour of the clearance path (subject of Jira MFM-102):
# floor 273.00 is applied before the round-down, so the shelf price lands at
# 272.99, one cent BELOW the floor. The golden files freeze this behaviour;
# MFM-102 changes the expected value to 273.09 and updates this assertion.
assert_grep "BR-P6 clearance floor (CURRENT behaviour, see MFM-102: 272.99 < floor 273.00)" \
    "$RPT" '^PRM2026123 10082345 NE  P +498\.00 +498\.00 +272\.99  FLOOR +UPDATED'

echo "== T05 DB2 after-state (CSV stand-in)"
IP="$WORK/ITEM_PRICE.csv"
PH="$WORK/PRICE_HIST.csv"
assert_eq "ITEM_PRICE row count unchanged (update in place)" \
    "$(tail -n +2 "$ROOT/data/db2/before/ITEM_PRICE.csv" | wc -l)" "$(tail -n +2 "$IP" | wc -l)"
assert_grep "ITEM_PRICE promo row carries promo id + dates + job" "$IP" '^10004410,NE,149\.00,119\.19,P,PRM2026120,2026-09-21,2026-10-05,PRCUPD01$'
assert_grep "ITEM_PRICE expired row reverted to R with blank promo" "$IP" '^10057890,NE,99\.99,99\.99,R,,,,PRCUPD01$'
assert_grep "ITEM_PRICE untouched row keeps original job"          "$IP" '^10078812,NE,749\.00,749\.00,R,,,,PRCLOAD0$'
assert_eq "PRICE_HIST is insert-only: before rows + 32 inserts" \
    "$(( $(tail -n +2 "$ROOT/data/db2/before/PRICE_HIST.csv" | wc -l) + 32 ))" "$(tail -n +2 "$PH" | wc -l)"
assert_grep "PRICE_HIST sequence continues from unload max (1003 -> 1004)" "$PH" '^1004,10057890,NE,79\.99,99\.99,PRM2026081,2026-09-21,EXPIRE,PRCUPD01$'
assert_no_grep "PRICE_HIST has no duplicate sequence numbers" <(cut -d, -f1 "$PH" | sort | uniq -d) '.'

echo "== T06 idempotency: re-run against the after-state changes nothing"
"$ROOT/scripts/run_job.sh" --no-compare --out "$TMP" > /dev/null 2>&1   # fresh SYSIN / sorted feed
export DD_SYSIN="$TMP/SYSIN.txt" DD_PROMOIN="$TMP/PROMOFEED.sorted.dat"
export DD_ITEMMAST="$ROOT/data/input/ITEMMAST.dat" DD_STORERGN="$ROOT/data/input/STORE_REGION.csv"
export DD_ITMPRCI="$ROOT/data/db2/expected_after/ITEM_PRICE.csv" DD_ITMPRCO="$TMP/ITEM_PRICE.rerun.csv"
export DD_PRCHSTI="$ROOT/data/db2/expected_after/PRICE_HIST.csv" DD_PRCHSTO="$TMP/PRICE_HIST.rerun.csv"
export DD_PRCRPT="$TMP/PRCUPD01.rerun.rpt"
"$ROOT/bin/PRCUPD01" > /dev/null 2>&1
assert_eq "second run updates 0 prices" "0" \
    "$(grep -E '^    PRICES UPDATED +[0-9]+$' "$TMP/PRCUPD01.rerun.rpt" | awk '{print $NF}')"
assert_eq "second run reports 31 unchanged (30 applied + 1 pre-existing)" "31" \
    "$(grep -E '^    PRICES UNCHANGED +[0-9]+$' "$TMP/PRCUPD01.rerun.rpt" | awk '{print $NF}')"
if cmp -s "$ROOT/data/db2/expected_after/ITEM_PRICE.csv" "$TMP/ITEM_PRICE.rerun.csv"; then
    ok "ITEM_PRICE after-state is a fixed point"
else
    bad "ITEM_PRICE after-state changed on re-run"
fi

echo "== T07 control-card validation"
export DD_SYSIN="$TMP/EMPTY.txt"; : > "$TMP/EMPTY.txt"
"$ROOT/bin/PRCUPD01" > "$TMP/norundate.log" 2>&1
assert_eq "missing RUNDATE -> RC 8" "8" "$?"
assert_grep "missing RUNDATE -> E002 message" "$TMP/norundate.log" 'E002 RUNDATE CONTROL CARD MISSING'

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
