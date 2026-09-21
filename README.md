# lowes-cobol-migration-demo

Sample enterprise COBOL/JCL batch estate for Devin migration demos (Lowe's).

Two self-contained mainframe batch jobs that build and run on plain Ubuntu with
GnuCOBOL, each with its JCL, copybooks, sample input, golden output and a
comparator, so Devin (or a human) can take a job from *understand* to *proved
equivalent* with file-level evidence.

| Job | Flavour | Pattern | Start here |
|---|---|---|---|
| **`GLPOST01`** daily GL posting | finance | **file in -> file out**: 2 fixed-width inputs, 3 fixed-width outputs, byte parity | `docs/DEMO_RUNBOOK.md`, `docs/tasks/GLPOST01.md` |
| `PRCUPD01` nightly promo price update | retail pricing | file + DB2 unload in -> DB2 after-state + report out (CSV stand-in for DB2) | section below |

The demo is built on `GLPOST01`. `PRCUPD01` stays as a second, more complex
example (sub-program CALL, DB2 stand-in, defect-preservation story).

## The demo flow (docs/DEMO_RUNBOOK.md)

1. **Ask Devin + DeepWiki** - understand the job from the JCL inward, with `file:line` citations.
2. **Ask plan mode -> Markdown task** - `docs/tasks/<JOB>.md`: issue, findings, layouts, reproduction, verification, acceptance criteria. Same text goes into Jira once the integration is enabled.
3. **Construct the Devin prompt** - the last block of the task file.
4. **Devin session** - baseline run of the COBOL first, implement, run on identical inputs, prove parity with `scripts/compare_<job>.sh`, PR.
5. **Devin Review + free chat** on the PR; humans approve.
6. **One playbook** (`playbooks/cobol-job-migration.md`) run in parallel child sessions to scale.

## GLPOST01 - daily general-ledger posting

```
GLTRANS.dat  (journal feed, FB 100)  --+
ACCTMAST.dat (chart of accounts, FB 60) +--> STEP010 SORT -> STEP020 GLPOST01 --> GLPOSTED.dat (posted ledger, FB 120)
                                                                              --> GLEXCEPT.dat (rejects, FB 80)
                                                                              --> GLPOST01.rpt (batch control report, 132)
```

```bash
sudo apt-get install -y gnucobol        # GnuCOBOL 3.x (Ubuntu 22.04 ships 3.1.2)
scripts/build.sh                        # -> bin/GLPOST01 (and bin/PRCUPD01)
scripts/run_glpost01.sh                 # SORT -> GLPOST01 -> compare_glpost01.sh ; exit = MAXCC (4 expected)
tests/run_glpost01_tests.sh             # 56-assertion regression harness (runs in CI)
```

Sample run: 31 journal lines in 4 batches -> 22 posted, 9 exceptions (one per
validation rule), 1 batch out of balance, RC 4. Outputs land in `work-glpost01/`.

**File parity** - `scripts/compare_glpost01.sh [output-dir]` compares each
output against `data/expected/GLPOST01/` through `scripts/compare_files.py`,
driven by the layouts in `layouts/*.json`:

| Layer | Question it answers | Verdict |
|---|---|---|
| 1 bytes | are the files identical (count, LRECL, every byte)? | the only layer that can say PASS |
| 2 decoded fields | *which* field differs, decoded (money with scale and sign)? | explains |
| 3 keyed reconciliation | which TRAN-IDs are missing / extra / changed? | explains |
| 4 control totals | counts, distinct keys, sum of every money field - zero tolerance | explains, fails on any drift |

A migrated implementation is proved by pointing the same script at its output
directory: `scripts/compare_glpost01.sh java/glpost01/target/out`. Baselines are
never edited, re-sorted or re-encoded to make a comparison pass.

Business rules (ids in source comments, task file and tests): `BR-V1..V7`
validation in fixed order (first failure wins -> `E001..E007`), `BR-P1..P3`
posting (sign by normal balance, dense POST-SEQ, `NO DESCRIPTION` default),
`BR-B1..B2` batch balance over all submitted lines and return codes. Full
detail with citations: `docs/tasks/GLPOST01.md`.

## Repository layout

```
cobol/src/GLPOST01.cbl        GL posting program (validate, post, exceptions, batch control report)
cobol/src/PRCUPD01.cbl        promo price update program; cobol/src/PRCRGN01.cbl called subprogram
cobol/copybooks/              GLTRNREC ACCTMAST GLPSTREC GLEXCREC (GLPOST01); ITEMMAST PROMOREC PRICEHST DCL* (PRCUPD01)
cobol/sql/ddl/                DB2 DDL used by PRCUPD01
jcl/GLPOST01.jcl              SORT -> GLPOST01 -> IEBCOMPR parity (regression environments)
jcl/PRCUPD01.jcl              SORT -> PRCUPD01 -> compare ; jcl/INVREPL01.jcl dependent job
schedules/nightly.txt         scheduler manifest for the pricing chain
layouts/*.json                machine-readable copybook layouts for compare_files.py
data/input/                   GLTRANS.dat ACCTMAST.dat (GL) ; PROMOFEED ITEMMAST STORE_REGION (pricing)
data/expected/GLPOST01/       golden GLPOSTED.dat GLEXCEPT.dat GLPOST01.rpt
data/db2/, data/expected/PRCUPD01.rpt   PRCUPD01 DB2 unloads and golden report
scripts/build.sh              cobc build of both programs
scripts/run_glpost01.sh, scripts/compare_glpost01.sh, scripts/compare_files.py   GL job + parity
scripts/run_job.sh, scripts/compare.sh                                           pricing job + golden diff
tests/run_glpost01_tests.sh   GLPOST01 harness (56)  ; tests/run_tests.sh  PRCUPD01 harness (48)
.github/workflows/ci.yml      installs GnuCOBOL, builds, runs both jobs + both harnesses
docs/DEMO_RUNBOOK.md          the demo, step by step, with every prompt
docs/tasks/GLPOST01.md        the Markdown task exemplar (what Ask plan mode produces; future Jira text)
docs/MIGRATION_SPEC_TEMPLATE.md  fuller spec template used by the PRCUPD01 example
docs/JIRA_SETUP.md, docs/JIRA_TO_DEVIN_DEMO_GUIDE.md   Jira board + ticket flow, for when the integration is enabled
playbooks/cobol-job-migration.md   the one playbook (!cobol_job_migrate)
.agents/skills/               repo skills Devin loads every session: mfm-jira-board (task protocol), cobol-ask (read-only analysis)
```

Environment variables `DD_<ddname>` map each program's `SELECT ... ASSIGN TO`
names to files, mirroring the JCL DD statements (GnuCOBOL convention).
`COB_LS_FIXED=1` keeps output records fixed-width (trailing spaces preserved).

## Second example - PRCUPD01 nightly promotional price update

```bash
scripts/run_job.sh                      # SORT -> PRCUPD01 -> compare ; MAXCC=4 expected
tests/run_tests.sh
```

| Step | Mainframe | Local | Purpose |
|------|-----------|-------|---------|
| STEP010 | `PGM=SORT` | `sort -k1.11,1.18 -k1.27,1.34 -k1.1,1.10` | sort promo feed on SKU / EFF-DATE / PROMO-ID |
| STEP020 | `PGM=PRCUPD01` | `bin/PRCUPD01` | phase 1 expire lapsed promos; phase 2 price each promo; phase 3 report |
| STEP030 | `PGM=ISRSUPC` | `scripts/compare.sh` | golden-master compare of report + DB2 after-state |

Business rules implemented (ids are referenced in source comments, tests and
the spec template):

| Rule | Description |
|------|-------------|
| BR-V1..V5 | validate promo type, SKU on item master, item not discontinued, effective-date window vs run date |
| BR-T1..T3 | target regions: store number -> its region (STORE_REGION); blank region -> all 5 regions; else the given region |
| BR-P1..P3 | percent off regular price / fixed price / BOGO (= regular / 2 per unit) |
| BR-R1..R3 | `PRCRGN01`: NC (AK/HI) suppresses BOGO and adds 8% freight uplift capped at regular; WC caps lumber discounts at 15% |
| BR-P4 | round **down** to a `.x9` price ending |
| BR-P5 | margin floor = unit cost x (1 + floor %); a floored price is rounded **up** to the next `.x9` |
| BR-P6 | clearance items (status C) take an extra 10% stacking markdown, then floor, then rounding |
| BR-E1 | promo prices whose end date has passed revert to regular price (phase 1) |
| BR-U1..U3 | update `ITEM_PRICE` in place, insert one `PRICE_HIST` row per change, `NOCHG` when the promo is already in effect |

> **Known defect (planted, documented):** BR-P6 applies the floor *before* the
> round-down, so a floored clearance price can land one cent below the floor
> (`10082345` at 272.99 vs floor 273.00 in the golden report). The golden files
> freeze this current behaviour; Jira ticket **MFM-102** fixes it. See
> `docs/JIRA_SETUP.md`.

## DB2 stand-in model (CSV dumps)

Direct DB2 access is not available in the demo estate, so the three tables are
represented as CSV unloads and the program's `8xxx-DB2-*` paragraphs read/write
those files. Each paragraph carries the `EXEC SQL` it stands in for as a
comment, and the DCLGEN copybooks (`DCLITMPR`, `DCLPRHST`, `DCLSTRGN`) keep the
host-variable structures, so the migration target can be verified against
"database state" without a database:

| Table | Before | After (golden) | Access pattern |
|-------|--------|----------------|----------------|
| `PRCDB.ITEM_PRICE` | `data/db2/before/ITEM_PRICE.csv` | `data/db2/expected_after/ITEM_PRICE.csv` | cursor `FOR UPDATE`, update in place, row count constant |
| `PRCDB.PRICE_HIST` | `data/db2/before/PRICE_HIST.csv` | `data/db2/expected_after/PRICE_HIST.csv` | insert-only, `HIST_SEQ` continues from unload max |
| `PRCDB.STORE_REGION` | `data/input/STORE_REGION.csv` | unchanged | read-only reference |

`diff data/db2/before/ITEM_PRICE.csv data/db2/expected_after/ITEM_PRICE.csv`
is the "DB2 before/after" view used in the demo.

## Data encoding

All data files are **ASCII, line-sequential** (not EBCDIC, not RECFM=FB
blocked), so the sample runs anywhere GnuCOBOL runs. Fixed-width records
(`PROMOREC`, `ITEMMAST`) keep their mainframe 80-byte layouts; numeric fields
are unsigned zoned decimal (`PIC 9(05)V99` -> `0014900` for 149.00), no
COMP-3. On a real estate the same programs would read EBCDIC FB datasets; the
copybooks are the contract, the encoding is a transport detail handled at
unload time. See the Q&A in `docs/DEMO_RUNBOOK.md`.

## Licence

MIT. Sample data, SKUs, prices and store names are fictitious.
