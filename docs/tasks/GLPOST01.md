# GLPOST01 - migrate the daily GL posting job to Java (Spring Batch) with file parity

> Task file produced from an **Ask Devin** planning conversation. Until the Jira
> integration is enabled this Markdown file *is* the ticket; the same content
> pastes into a Jira issue unchanged. It is the single input to the Devin
> session that does the work (see "Devin prompt" at the bottom).

| | |
|---|---|
| Job | `GLPOST01` - daily general-ledger posting (`jcl/GLPOST01.jcl`) |
| Program | `cobol/src/GLPOST01.cbl` (single program, no CALLs, no SQL) |
| Playbook | `playbooks/cobol-job-migration.md` (`!cobol_job_migrate`) |
| Owner | Finance systems - GL close |
| Proof required | file parity: legacy and Java outputs byte-identical on the same input |

## Issue

GLPOST01 is one of the nightly finance jobs in the mainframe decommission
scope. It reads the sub-ledger journal feed, validates every line against the
chart of accounts, posts valid lines to the posted-ledger file, writes rejects
to the exceptions file and prints the batch control report that the GL close
team reconciles every morning. Migrate it to a Java Spring Batch job that
produces the **same three output files** from the **same two input files**.

## What Ask Devin found (with citations)

**Job flow** - `jcl/GLPOST01.jcl`
- `STEP010` SORT: `SORT FIELDS=(56,8,CH,A,19,10,CH,A,1,10,CH,A)` = BATCH-ID / ACCT-NO / TRAN-ID (line 50).
- `STEP020` `PGM=GLPOST01`, `COND=(4,LT,STEP010)` (line 57). DD -> `SELECT` map (`GLPOST01.cbl` 66-81):
  `SYSIN` control card, `GLTRANS` sorted feed, `ACCTMAST` chart of accounts,
  `GLPOSTED` posted ledger, `GLEXCEPT` exceptions, `GLRPT` report.
- `STEP030` IEBCOMPR file parity - regression environments only (line 85-91).
- Restartable from STEP010; outputs are new GDG generations (line 26).

**Files** (all fixed-block, ASCII in this repo, EBCDIC on the host)

| DD | Copybook | RECFM/LRECL | Key |
|---|---|---|---|
| GLTRANS  in  | `cobol/copybooks/GLTRNREC.cpy` | FB 100 | TRAN-ID |
| ACCTMAST in  | `cobol/copybooks/ACCTMAST.cpy` | FB 60  | ACCT-NO |
| GLPOSTED out | `cobol/copybooks/GLPSTREC.cpy` | FB 120 | TRAN-ID (POST-SEQ dense 1..n) |
| GLEXCEPT out | `cobol/copybooks/GLEXCREC.cpy` | FB 80  | TRAN-ID |
| GLRPT    out | report lines 132 | text | - |

Machine-readable layouts for the comparator: `layouts/GLTRANS.json`,
`layouts/GLPOSTED.json`, `layouts/GLEXCEPT.json`.

**Business rules** - `GLPOST01.cbl` header lines 30-50, implemented in:
- Validation `2200-VALIDATE-LINE` / `2210-LOOKUP-ACCOUNT` (486-537). First
  failing rule wins, in this order: BR-V1 DR-CR in {D,C} -> E004; BR-V2 amount > 0
  -> E005; BR-V3 currency = USD -> E006; BR-V4 account on master -> E001;
  BR-V5 not closed -> E002; BR-V6 not frozen -> E003; BR-V7 post date in RUNDATE
  period and <= RUNDATE -> E007.
- Posting `2300-POST-LINE` (538-572): BR-P1 signed amount is + when DR-CR equals
  the account's normal balance, else - (`SIGN LEADING SEPARATE`); BR-P2 POST-SEQ
  restarts at 1 each run; BR-P3 blank description -> `NO DESCRIPTION`;
  ACCT-TYPE copied from the master; RUN-DATE stamped on every record.
- Batch control `3000-BATCH-BREAK` (624-654): BR-B1 debit and credit totals are
  accumulated over **all submitted lines, rejected ones included**; BALANCED /
  OUT OF BALANCE per batch on the report.
- Return code (`WS-RETURN-CODE`, set in `2400-REJECT-LINE` 617 and `3000-BATCH-BREAK`
  640, moved to `RETURN-CODE` in `0000-MAIN` 322): BR-B2 any rejection or
  out-of-balance batch -> RC 4; empty feed or missing/bad control card -> RC 8;
  file-status errors and master table overflow (300 accounts) -> RC 16.

**Observed behaviour to preserve** (do not "fix" during migration)
- An E004 (bad DR-CR) line is counted in neither batch total, so a batch with
  one bad-code line shows OUT OF BALANCE even if the rest balances. Sample:
  `MAN09211`.
- Amounts are compared with zero tolerance; there is no rounding anywhere in
  the job.
- Report batch totals print unsigned (`Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99`); the per-type
  NET column carries a trailing minus (e.g. `214,284.26-`).
- `2210-LOOKUP-ACCOUNT` (522-533) `SEARCH`es all 300 `WS-ACCT-ENTRY` slots,
  not just the `WS-ACCT-COUNT` loaded ones; unloaded slots are spaces. A line
  whose `GLT-ACCT-NO` is all spaces therefore matches the first empty slot and
  is posted (blank status passes E002/E003; blank type falls through the type
  classification) instead of being rejected E001. Not in the sample data; the
  Java job must reproduce the same outcome on identical input, and the finding
  goes on a separate maintenance task.
- `1100-READ-CONTROL-CARDS` (364-372) accepts any 8 characters after
  `RUNDATE=`: it checks the prefix only, `MOVE`s the text into `WS-RUNDATE`
  and derives `WS-RUN-PERIOD` from the first six. A non-numeric or impossible
  calendar value (`RUNDATE=20260931`) is not RC 8; it drives BR-V7 as-is and
  is written into every GLPOSTED `RUN-DATE`. The RC 8 "bad control card" path
  fires only when the prefix is missing. Not in the sample run; the migration
  reproduces it, and the finding goes on a separate maintenance task.
- `WS-FS-RPT` is checked only after `OPEN` (338); none of the 27
  `WRITE REPORT-REC` statements test it, so a failed report write does not
  change the return code. Not reproducible with the sample data.
- `jcl/GLPOST01.jcl` STEP030 (IEBCOMPR, `COND=(4,LT,STEP020)`) runs whenever
  STEP020 ends 0 or 4, i.e. on every normal run, although the comments call it
  regression-only, and it compares GLPOSTED only. `scripts/run_glpost01.sh`
  emulates it as the three-file `compare_glpost01.sh`. Kept as-is: the JCL is
  the legacy artefact being migrated, not the migration.

**Downstream** - `GLPOSTED.DAILY(+1)` is consumed by the GL close jobs;
`GLEXCEPT.DAILY(+1)` feeds the suspense-clearing workflow. Neither is in this repo.

## Reproduce the legacy run (the baseline)

```bash
scripts/build.sh                 # cobc -> bin/GLPOST01
scripts/run_glpost01.sh          # SORT -> GLPOST01 -> compare_glpost01.sh ; MAXCC=4 expected
tests/run_glpost01_tests.sh      # 67-assertion harness (also runs in CI)
```

Sample input: `data/input/GLTRANS.dat` (31 lines, 4 batches) +
`data/input/ACCTMAST.dat` (15 accounts). Golden outputs the COBOL job wrote
for that input: `data/expected/GLPOST01/` (22 posted, 9 exceptions, 41-line
report, one out-of-balance batch, RC 4).

## Verification (how "done" is proved)

Run the Java job on **exactly** the same `GLTRANS.dat` / `ACCTMAST.dat` /
`RUNDATE=20260921`, write to its own directory, then:

```bash
scripts/compare_glpost01.sh <java-output-dir>
```

The comparator works in layers and never edits the baseline:
1. bytes - record count, LRECL, every byte of every record;
2. decoded fields - which field differs, decoded (money with scale/sign);
3. keyed reconciliation on TRAN-ID - missing / extra / changed keys;
4. control totals - counts, distinct keys, sum of every money field, zero tolerance.

Exit 0 only when all three files are byte-identical. Layers 2-4 exist to
**explain** a difference, not to accept it.

## Acceptance criteria

- [ ] `scripts/compare_glpost01.sh <java-out>` exits 0 on the sample input (all three files IDENTICAL).
- [ ] Java job return code is 4 on the sample input, 0 on a clean balanced feed, 8 on an empty feed or bad control card (see `tests/run_glpost01_tests.sh` G08/G09).
- [ ] Output records are fixed width - 120 / 80 / 132 - with trailing spaces preserved, no line-ending or encoding drift.
- [ ] The COBOL job, copybooks, JCL and goldens are **untouched**. Any golden change is a separate PR with a finance approver.
- [ ] PR description contains the tail of the comparator output and the `tests/run_glpost01_tests.sh` summary, both produced in the session (no typed numbers).
- [ ] Every rule BR-V1..V7, BR-P1..P3, BR-B1..B2 maps to a named Java class/method in the PR description.

**Blockers, not judgement calls:** any unexplained byte difference; any
difference in a money, count or key field; any change to a baseline file.

## Devin prompt (paste into a new session)

```
Read docs/tasks/GLPOST01.md and follow playbooks/cobol-job-migration.md.
Migrate GLPOST01 to a Spring Batch job under java/glpost01/ (Java 17, Maven,
no database). Baseline first: build and run the COBOL job and confirm
scripts/run_glpost01.sh ends MAXCC=4 with compare PASS before you write any
Java. Then implement, run the Java job on the same inputs, and prove parity
with scripts/compare_glpost01.sh <java-output-dir>. Do not modify anything
under cobol/, jcl/, data/ or layouts/. Open a PR whose description includes
the comparator tail and the rule -> class mapping.
```
