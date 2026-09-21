# lowes-cobol-migration-demo

Sample enterprise COBOL/JCL batch estate for Devin migration demos (Lowe's).

A small, self-contained, retail-flavoured slice of a mainframe pricing estate:
one representative nightly JCL job (`PRCUPD01`, promotional price update) with
its COBOL programs, copybooks, DB2 schema, scheduler dependencies and golden
test data. Everything builds and runs on plain Ubuntu with GnuCOBOL, so Devin
(or a human) can take the job through **explore -> specify -> plan -> implement
-> verify** with byte-for-byte proof, tracked as two Jira tickets.

## What is in here

```
cobol/src/PRCUPD01.cbl        main batch program (~1,000 lines incl. comments; the business logic
                              lives in paragraphs 2000-3100, the CSV/DB2 stand-in layer in 8000-8910)
cobol/src/PRCRGN01.cbl        called subprogram: region / store override rules (NC freight, WC lumber)
cobol/copybooks/              ITEMMAST, PROMOREC, PRICEHST record layouts; DCL* DB2 DCLGEN copybooks;
                              PRCRGNCA call interface
cobol/sql/ddl/                DB2 DDL for ITEM_PRICE, PRICE_HIST, STORE_REGION (+ PRICE_REGION)
jcl/PRCUPD01.jcl              the job: STEP010 SORT -> STEP020 PRCUPD01 -> STEP030 compare (PROC-style)
jcl/INVREPL01.jcl             dependent job (thin) that consumes the ITEM_PRICE after-state
schedules/nightly.txt         scheduler manifest: job order, predecessors, restart notes
data/input/                   promo feed (80-byte), item master (80-byte), STORE_REGION unload (CSV)
data/db2/before/              ITEM_PRICE / PRICE_HIST unloads before the run
data/db2/expected_after/      golden after-state unloads
data/expected/PRCUPD01.rpt    golden audit / exception report
scripts/build.sh              cobc build -> bin/PRCUPD01
scripts/run_job.sh            local emulation of the three JCL steps
scripts/compare.sh            golden-master diff (exit 8 on any mismatch)
tests/run_tests.sh            41-assertion regression harness (runs in CI)
.github/workflows/ci.yml      installs GnuCOBOL, builds, runs job + tests
docs/DEMO_RUNBOOK.md          30-minute Devin demo script
docs/JIRA_TO_DEVIN_DEMO_GUIDE.md  Jira ticket -> Devin session -> verified PR; estate replication; verification loop
docs/JIRA_SETUP.md            "Mainframe Modernization" board + tickets MFM-101 / MFM-102
docs/MIGRATION_SPEC_TEMPLATE.md  the "specify" artefact Devin produces per job
playbooks/                    Devin playbook drafts: ask mode (!cobol_ask), job migration (!jcl_migrate), in-place fix (!cobol_fix)
.agents/skills/               Repo skills Devin loads every session: mfm-jira-board (board protocol), cobol-ask (read-only analysis)
```

## Build and run locally

```bash
sudo apt-get install -y gnucobol        # GnuCOBOL 3.x (Ubuntu 22.04 ships 3.1.2)
scripts/build.sh                        # -> bin/PRCUPD01
scripts/run_job.sh                      # SORT -> PRCUPD01 -> compare ; exit code = job MAXCC
tests/run_tests.sh                      # full regression harness
```

`run_job.sh` ends with `MAXCC=4` on the sample data. That is the *expected*
outcome: return code 4 means "warnings on the report" (skipped and rejected
promo records are part of the sample deliberately). `compare.sh` exits 0 when
the report and both DB2 after-state CSVs are byte-identical to the golden
files, 8 otherwise. Outputs land in `work/`.

Environment variables `DD_<ddname>` map the program's `SELECT ... ASSIGN TO`
names to files, mirroring the JCL DD statements (GnuCOBOL convention).

## The job: PRCUPD01 nightly promotional price update

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

## Demo map

1. `docs/DEMO_RUNBOOK.md` - the 30-minute script, prompts for Devin, what to
   watch, fallbacks, Q&A.
2. `docs/JIRA_SETUP.md` - the board and the two tickets Devin picks up.
3. `docs/JIRA_TO_DEVIN_DEMO_GUIDE.md` - how a ticket becomes a session
   (integration, Ask Devin, API), how the estate is replicated, and the
   oracle-first verification loop Devin must follow.
4. `docs/MIGRATION_SPEC_TEMPLATE.md` - the artefact Devin fills in during
   **specify**.
5. `playbooks/` - reusable Devin playbooks: `!cobol_ask` (scoping only), `!jcl_migrate`, `!cobol_fix`.
6. `.agents/skills/mfm-jira-board/SKILL.md` - how every session reads and updates the MFM Jira board.

## Licence

MIT. Sample data, SKUs, prices and store names are fictitious.
