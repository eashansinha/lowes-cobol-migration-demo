#!/usr/bin/env bash
# run_glpost01_tests.sh - regression harness for the GLPOST01 daily GL posting job.
#
# Builds the load module, runs the job end to end against data/input and
# asserts on file parity with data/expected/GLPOST01 plus business-rule spot
# checks that pin the behaviour a migrated implementation must reproduce.
# Exit 0 = all tests passed.
#
# Usage: tests/run_glpost01_tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/work-glpost01"
TMP="$ROOT/work-glpost01-tests"
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
total() {                # total <label> -> value from RUN TOTALS block (counts)
    grep -E "^  $1 +[0-9]+ *$" "$WORK/GLPOST01.rpt" | awk '{print $NF}'
}
amount() {               # amount <label> -> value from RUN TOTALS block (money)
    grep -E "^  $1 +[0-9,.-]+ *$" "$WORK/GLPOST01.rpt" | awk '{print $NF}'
}
field() {                # field <file> <key-regex> <start> <length> -> substring of matching record
    grep -E -- "$2" "$1" | head -1 | cut -c"$3"-"$(( $3 + $4 - 1 ))"
}

echo "== G01 build"
if "$ROOT/scripts/build.sh" > "$ROOT/work-glpost01-build.log" 2>&1; then
    ok "cobc build of GLPOST01"
else
    bad "cobc build failed" "$(tail -5 "$ROOT/work-glpost01-build.log")"
    echo; echo "$PASS passed, $FAIL failed"; exit 1
fi

echo "== G02 end-to-end job run + file parity"
"$ROOT/scripts/run_glpost01.sh" > "$ROOT/work-glpost01-run.log" 2>&1
RC=$?
assert_eq "job MAXCC is 4 (exceptions + one out-of-balance batch)" "4" "$RC"
assert_grep "compare_glpost01.sh reports PASS" "$ROOT/work-glpost01-run.log" 'compare_glpost01.sh: PASS'
assert_grep "GLPOSTED IDENTICAL"  "$ROOT/work-glpost01-run.log" 'RESULT GLPOSTED: IDENTICAL'
assert_grep "GLEXCEPT IDENTICAL"  "$ROOT/work-glpost01-run.log" 'RESULT GLEXCEPT: IDENTICAL'
assert_grep "GLRPT IDENTICAL"     "$ROOT/work-glpost01-run.log" 'RESULT report: IDENTICAL'

echo "== G03 record contract (RECFM=FB)"
assert_eq "GLPOSTED every record is LRECL 120" "120" "$(awk '{print length($0)}' "$WORK/GLPOSTED.dat" | sort -u | tr '\n' ' ' | xargs)"
assert_eq "GLEXCEPT every record is LRECL 80"  "80"  "$(awk '{print length($0)}' "$WORK/GLEXCEPT.dat" | sort -u | tr '\n' ' ' | xargs)"
assert_eq "GLRPT every line is 132"            "132" "$(awk '{print length($0)}' "$WORK/GLPOST01.rpt" | sort -u | tr '\n' ' ' | xargs)"
assert_eq "posted + rejected = read (22 + 9 = 31)" "31" "$(( $(wc -l < "$WORK/GLPOSTED.dat") + $(wc -l < "$WORK/GLEXCEPT.dat") ))"

echo "== G04 run totals"
assert_eq "accounts on master"        "15" "$(total 'ACCOUNTS ON MASTER')"
assert_eq "transactions read"         "31" "$(total 'TRANSACTIONS READ')"
assert_eq "transactions posted"       "22" "$(total 'TRANSACTIONS POSTED')"
assert_eq "transactions rejected"     "9"  "$(total 'TRANSACTIONS REJECTED')"
assert_eq "batches read"              "4"  "$(total 'BATCHES READ')"
assert_eq "batches out of balance"    "1"  "$(total 'BATCHES OUT OF BALANCE')"
assert_eq "posted debit total"        "767,836.49" "$(amount 'POSTED DEBIT TOTAL')"
assert_eq "posted credit total"       "800,281.74" "$(amount 'POSTED CREDIT TOTAL')"
assert_eq "posted net signed"         "232,127.73" "$(amount 'POSTED NET SIGNED')"

echo "== G05 business rules - validation (one exception per line, first failure wins)"
EXC="$WORK/GLEXCEPT.dat"
assert_grep "BR-V4 E001 unknown account 9999999999"        "$EXC" '^T0000004059999999999E001ACCOUNT NOT ON MASTER'
assert_grep "BR-V5 E002 closed account 6900900000"         "$EXC" '^T0000004036900900000E002ACCOUNT CLOSED'
assert_grep "BR-V6 E003 frozen account 6200300000"         "$EXC" '^T0000001066200300000E003ACCOUNT FROZEN - NO POSTING'
assert_grep "BR-V1 E004 DR-CR code X"                      "$EXC" '^T0000004071500100000E004INVALID DR/CR CODE .*X'
assert_grep "BR-V2 E005 zero amount"                       "$EXC" '^T0000002081100200000E005ZERO AMOUNT .*0000000000000D'
assert_grep "BR-V3 E006 CAD suspended (both legs)"         "$EXC" '^T000000206.*E006NON-USD CURRENCY SUSPENDED'
assert_grep "BR-V3 E006 CAD suspended (credit leg)"        "$EXC" '^T000000207.*E006NON-USD CURRENCY SUSPENDED'
assert_grep "BR-V7 E007 August post date in September run" "$EXC" '^T0000003056000100000E007POST DATE OUT OF PERIOD'
assert_eq   "E006 precedes E001: CAD line on a valid account is E006 not E001" \
    "E006" "$(field "$EXC" '^T000000206' 21 4)"
assert_no_grep "rejected lines never reach GLPOSTED" "$WORK/GLPOSTED.dat" 'T000000106|T000000206|T000000207|T000000208|T000000305|T000000306|T000000403|T000000405|T000000407'

echo "== G06 business rules - posting"
PST="$WORK/GLPOSTED.dat"
assert_eq "BR-P1 debit to debit-normal asset is +  (T000000102 +125000.00)" "+0000012500000" "$(field "$PST" 'T000000102' 43 14)"
assert_eq "BR-P1 credit to debit-normal asset is -  (T000000107 -60000.00)" "-0000006000000" "$(field "$PST" 'T000000107' 43 14)"
assert_eq "BR-P1 credit to credit-normal liability is + (T000000101)"       "+0000012500000" "$(field "$PST" 'T000000101' 43 14)"
assert_eq "BR-P1 debit to credit-normal liability is -  (T000000108)"       "-0000006000000" "$(field "$PST" 'T000000108' 43 14)"
assert_eq "BR-P2 POST-SEQ restarts at 0000001"          "0000001" "$(head -1 "$PST" | cut -c1-7)"
assert_eq "BR-P2 POST-SEQ is dense (last = 0000022)"    "0000022" "$(tail -1 "$PST" | cut -c1-7)"
assert_eq "BR-P3 blank description posted as NO DESCRIPTION" "NO DESCRIPTION" "$(field "$PST" 'T000000409' 73 30 | sed 's/ *$//')"
assert_eq "ACCT-TYPE is copied from the master (3000100000 -> Q)" "Q" "$(field "$PST" 'T000000409' 36 1)"
assert_eq "RUN-DATE stamped on every posted record" "1" "$(cut -c103-110 "$PST" | sort -u | wc -l)"
assert_eq "output order = sort order BATCH-ID / ACCT-NO / TRAN-ID" \
    "$(awk '{print substr($0,65,8) substr($0,26,10) substr($0,8,10)}' "$PST" | LC_ALL=C sort | md5sum | cut -d' ' -f1)" \
    "$(awk '{print substr($0,65,8) substr($0,26,10) substr($0,8,10)}' "$PST" | md5sum | cut -d' ' -f1)"

echo "== G07 business rules - batch control"
RPT="$WORK/GLPOST01.rpt"
assert_grep "BR-B1 AP092101 balanced although one line rejected (totals include rejects)" "$RPT" '^  AP092101 +8 +7 +1 +208,075\.50 +208,075\.50  BALANCED'
assert_grep "BR-B1 MAN09211 out of balance (E004 line counted in neither total)"           "$RPT" '^  MAN09211 +9 +6 +3 +99,995\.25 +112,995\.25  OUT OF BALANCE'
assert_grep "BR-B1 PAY09211 balanced with two E007 rejects"                                "$RPT" '^  PAY09211 +6 +4 +2 +422,250\.00 +422,250\.00  BALANCED'
assert_grep "posted-by-type ASSET net is negative (credits exceed debits)"                 "$RPT" '^  A ASSET +10 +183,210\.99 +397,495\.25 +214,284\.26-'

echo "== G08 clean run: balanced input with no exceptions -> RC 0, empty GLEXCEPT"
rm -rf "$TMP"; mkdir -p "$TMP"
grep -E '^T0000001(01|02|03|04|07|08)' "$ROOT/data/input/GLTRANS.dat" > "$TMP/GLTRANS.clean.dat"
"$ROOT/scripts/run_glpost01.sh" --no-compare --out "$TMP/run" --trans "$TMP/GLTRANS.clean.dat" > "$TMP/clean.log" 2>&1
assert_eq "MAXCC is 0" "0" "$?"
assert_eq "GLEXCEPT is empty" "0" "$(wc -l < "$TMP/run/GLEXCEPT.dat")"
assert_grep "report shows 0 rejected" "$TMP/run/GLPOST01.rpt" '^  TRANSACTIONS REJECTED +0 *$'
assert_grep "report shows highest RC 0" "$TMP/run/GLPOST01.rpt" '^  HIGHEST RETURN CODE +0 *$'

echo "== G09 control-card and empty-feed handling"
: > "$TMP/GLTRANS.empty.dat"
"$ROOT/scripts/run_glpost01.sh" --no-compare --out "$TMP/empty" --trans "$TMP/GLTRANS.empty.dat" > "$TMP/empty.log" 2>&1
assert_eq "empty feed -> RC 8" "8" "$?"
assert_grep "empty feed message" "$TMP/empty.log" 'EMPTY GLTRANS FEED'
mkdir -p "$TMP/badcard"; printf 'RUNDT=20260921\n' > "$TMP/badcard/SYSIN.txt"
COB_LS_FIXED=1 DD_SYSIN="$TMP/badcard/SYSIN.txt" DD_GLTRANS="$WORK/GLTRANS.sorted.dat" \
  DD_ACCTMAST="$ROOT/data/input/ACCTMAST.dat" DD_GLPOSTED="$TMP/badcard/p" DD_GLEXCEPT="$TMP/badcard/e" \
  DD_GLRPT="$TMP/badcard/r" "$ROOT/bin/GLPOST01" > "$TMP/badcard.log" 2>&1
assert_eq "bad control card -> RC 8" "8" "$?"
assert_grep "bad control card message" "$TMP/badcard.log" 'BAD CONTROL CARD'

echo "== G10 file-parity tool catches a divergent target"
mkdir -p "$TMP/diverge"
sed -e '/T000000406/d' \
    -e 's/^\(0000017T000000409.\{55\}\)NO DESCRIPTION  /\1                /' \
    "$WORK/GLPOSTED.dat" > "$TMP/diverge/GLPOSTED.dat"
"$ROOT/scripts/compare_files.py" --layout "$ROOT/layouts/GLPOSTED.json" \
    --baseline "$ROOT/data/expected/GLPOST01/GLPOSTED.dat" --target "$TMP/diverge/GLPOSTED.dat" \
    > "$TMP/diverge.log" 2>&1
assert_eq "divergent target -> exit 8" "8" "$?"
assert_grep "layer 3 names the missing key"           "$TMP/diverge.log" 'missing : T000000406'
assert_grep "layer 2 decodes the changed field"       "$TMP/diverge.log" 'key T000000409 +DESCRIPTION +NO DESCRIPTION -> *$'
assert_grep "layer 4 flags the money total"           "$TMP/diverge.log" 'sum SIGNED-AMT +232127\.73 +232872\.98  DIFFERS'
assert_grep "verdict is DIFFERENT"                    "$TMP/diverge.log" 'RESULT GLPOSTED: DIFFERENT'

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
