# Demo runbook: PRCUPD01 through Devin, end to end (30 minutes)

Audience: Omkar (Lowe's) with Eashan (Cognition) driving. No slides. One
representative JCL job, two Jira tickets, Devin does the work live while we
talk about what it is doing. Everything shown is in this repository.

**Storyline in one line:** *"Give Devin a JCL job and a Jira ticket. It
explores the estate, writes the spec, plans, implements, and proves
equivalence byte-for-byte against the DB2 after-state - then moves the ticket."*

---

## 0. Before the meeting (Eashan, ~20 min the day before)

### 0.1 Repo indexing (Devin -> Settings -> Repositories)

Index **only** the repos relevant to the storyline; do not index the whole
GitHub org. For this demo:

| Repo | Index? | Why |
|------|--------|-----|
| `eashansinha/lowes-cobol-migration-demo` | yes | the estate under test |
| `eashansinha/acaps-legacy-demo` | optional | a second COBOL estate to show cross-repo search ("where else is `.x9` rounding done?") |
| anything unrelated | no | keeps Devin's search focused and answers Q1 below honestly |

Talking point for Omkar: at Lowe's scale you index per **domain / batch stream**
(e.g. "pricing nightly" = the 40-60 JCL members, their PROCLIB, copybook
library and DCLGEN library), not the entire PDS estate at once.

### 0.2 Environment blueprint (Devin -> Settings -> Environment for the repo)

Nothing beyond GnuCOBOL. Blueprint steps:

```bash
# Install
sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends gnucobol
# Verify
cobc --version && scripts/build.sh && scripts/run_job.sh ; echo "MAXCC=$?"   # expect MAXCC=4
# Maintain (each session)
scripts/build.sh
```

For MFM-101 also add `sudo apt-get install -y openjdk-17-jdk maven` (Devin
will do this itself if missing, but pre-installing saves 2 minutes live).

### 0.3 Secrets

**None.** No DB2, no mainframe, no MQ credentials are needed. Say this out
loud - it is the point of the CSV stand-in model.

### 0.4 Jira

Follow `docs/JIRA_SETUP.md`: board **Mainframe Modernization**, tickets
MFM-101 and MFM-102 in **Ready for Devin**. The live sandbox is
[MFM on cog-gtm.atlassian.net](https://cog-gtm.atlassian.net/jira/software/projects/MFM/boards/2594);
there the tickets are keyed `MFM-1` (= MFM-101) and `MFM-2` (= MFM-102), so
substitute those keys in the prompts. If the Jira integration is not
connected to this Devin org, keep the board open in a browser tab and move
tickets by hand while narrating - the prompt text below contains everything
Devin needs regardless.

### 0.5 Warm-up

Start a throwaway Devin session on the repo an hour before: "Run
`tests/run_tests.sh` and tell me the MAXCC and how many tests pass." This
confirms the blueprint, the snapshot and GnuCOBOL. Expect: MAXCC=4, 49 passed.

---

## 1. Minute-by-minute

Timings assume a 30-minute slot. MFM-101 is the main act; MFM-102 runs in a
**second session started at minute 3** so it finishes while MFM-101 is still
implementing. If you only have one session, do MFM-102 first (it is fast) and
show MFM-101 from a pre-run session (fallback, section 3).

| Min | Phase | Eashan does | Omkar watches |
|-----|-------|-------------|---------------|
| 0-3 | Set the scene | Open the repo. Show `jcl/PRCUPD01.jcl` (3 steps, DD names), `schedules/nightly.txt` (INVREPL01 depends on it), `data/db2/before/ITEM_PRICE.csv` ("this is DB2, unloaded"). Run `scripts/run_job.sh` in a terminal: MAXCC=4, compare PASS. | A real-looking job, real DB2 shape, no mainframe needed to run it. |
| 3-5 | Kick off both tickets | Move MFM-101 to **Ready for Devin** (or paste Prompt A into a new session). Start a second session with Prompt B (MFM-102). Tickets move to **In Progress**. | Jira is the entry point; Devin picks work off the board. |
| 5-9 | **Explore** (MFM-101) | Narrate Devin's actions: it reads the JCL first, follows DD names into `SELECT ... ASSIGN`, opens copybooks, finds `CALL 'PRCRGN01'`, reads the DDL, reads the scheduler manifest. Point at its plan / notes. | Devin builds the dependency picture (job -> program -> subprogram -> copybooks -> tables -> downstream job) rather than translating line by line. Ask it a question live: *"which downstream jobs break if ITEM_PRICE column order changes?"* |
| 9-14 | **Specify** | Devin writes `docs/specs/PRCUPD01-spec.md` from the template. Open it as it lands. Highlight the business-rules table with BR ids and the *evidence* column (paragraph names). Look for BR-P6 flagged as "observed defect - preserve". | The spec is the reviewable artefact a Lowe's SME signs off, and it is traceable to source lines. Devin found the planted defect by reading, not by being told. |
| 14-16 | **Plan** | Devin posts its Spring Batch layout (steps / reader / processor / writer, CSV repositories behind an interface). Approve or nudge ("keep the report writer a plain 132-column formatter"). | You steer at the plan stage, cheaply, before code exists. |
| 16-22 | **Implement** | Switch to the MFM-102 session, which by now has: run the tests to prove current behaviour, changed `2620-CLEARANCE-PRICING`, updated three golden files and one test, re-run everything. Show its PR: 4 report lines change, 4 `ITEM_PRICE` rows, 4 `PRICE_HIST` rows, totals identical. Ticket -> **In Review**. | Section 2 below. This is the "we also need to keep the COBOL alive for five more years" story: safe in-place change with regression proof. |
| 22-27 | **Verify** (MFM-101) | Back to MFM-101. Devin has run COBOL and Java on the same inputs and run `scripts/compare.sh java/target/out`. Show the compare output (`MATCH ... identical` x3). Show CI running both. PR open, ticket -> **In Review**. | Equivalence is a *diff*, not an opinion. Report + DB2 after-state byte-identical. |
| 27-30 | Close | Move MFM-102 to **Verified** after re-running `scripts/run_job.sh` on its branch. Q&A (section 4). | What it would take to do this for 400 jobs (Q5). |

### Prompt A - MFM-101 (paste verbatim, or let the Jira integration deliver it)

```
Pick up Jira ticket MFM-101 in project MFM: "Migrate PRCUPD01 nightly promo
price job to Java (Spring Batch) with equivalence verification".
Repository eashansinha/lowes-cobol-migration-demo, branch main. Follow
playbooks/cobol-job-migration.md. Work in this order and post a short update
at the end of each phase: (1) EXPLORE the job jcl/PRCUPD01.jcl, both COBOL
programs, all copybooks, cobol/sql/ddl and schedules/nightly.txt; (2) SPECIFY
by filling docs/MIGRATION_SPEC_TEMPLATE.md into docs/specs/PRCUPD01-spec.md
with evidence for every rule, preserving current behaviour including any
defects you notice (flag them, do not fix them); (3) PLAN the Spring Batch
layout and wait for my OK; (4) IMPLEMENT under java/ (Java 17, Maven, Spring
Batch 5, CSV-backed repositories behind an interface); (5) VERIFY by running
COBOL (scripts/run_job.sh) and Java on the same inputs and running
scripts/compare.sh against the Java output directory until it exits 0, then
add the Java run to .github/workflows/ci.yml. Open a PR against main with the
plan, spec link and compare output, and move MFM-101 to In Review.
```

### Prompt B - MFM-102 (paste verbatim)

```
Pick up Jira ticket MFM-102 in project MFM: "PRCUPD01: fix price-floor
rounding defect for clearance items and add regression test". Repository
eashansinha/lowes-cobol-migration-demo, branch main. Follow
playbooks/cobol-job-maintenance.md. First run tests/run_tests.sh and quote
the BR-P6 line to prove the current behaviour (272.99 below floor 273.00).
Then fix paragraph 2620-CLEARANCE-PRICING in cobol/src/PRCUPD01.cbl so the
clearance path rounds down, applies the floor, and rounds UP when floored,
exactly like 2610-STANDARD-PRICING. Update the three golden files to the
expected values in the ticket and nothing else, update the BR-P6 test to
expect 273.09, and add a regression assertion that no FLOOR row on the report
is below its floor. Re-run scripts/run_job.sh (must end MAXCC=4 with compare
PASS) and tests/run_tests.sh. Open a PR against main with a before/after
excerpt of the report and the ITEM_PRICE diff, and move MFM-102 to In Review.
```

---

## 2. How the verification is shown

Two artefacts, both diffs, both in the PR and reproducible from a terminal:

**Report diff (audit / exception report, 132 columns)**

```bash
scripts/run_job.sh --no-compare            # produce work/PRCUPD01.rpt on the branch
diff data/expected/PRCUPD01.rpt work/PRCUPD01.rpt
```

For MFM-101 the diff is **empty** (Java output vs golden). For MFM-102 it is
exactly four detail lines (`272.99 -> 273.09`); totals untouched.

**DB2 before / after (CSV stand-in for `PRCDB.ITEM_PRICE`, `PRCDB.PRICE_HIST`)**

```bash
diff data/db2/before/ITEM_PRICE.csv data/db2/expected_after/ITEM_PRICE.csv   # what the job did to DB2
diff data/db2/expected_after/ITEM_PRICE.csv work/ITEM_PRICE.csv              # did the new code do the same?
wc -l data/db2/before/PRICE_HIST.csv data/db2/expected_after/PRICE_HIST.csv  # insert-only: +32 rows
```

`scripts/compare.sh` runs all three comparisons and exits 8 on any byte
difference. Say explicitly: *on the real estate the "after" file is a DB2
unload from the test LPAR; the compare is identical.*

**Jira movement**

`Ready for Devin -> In Progress` when Devin starts (session link in a comment)
-> `In Review` when the PR is open (PR link + compare output in a comment) ->
`Verified` by Eashan after re-running compare -> `Done` on merge.

---

## 3. Fallbacks

| If | Then |
|----|------|
| Devin session slow to start / snapshot rebuilding | Start with MFM-102 in the terminal by hand for 2 minutes: show the defect line in the golden report, then open the pre-recorded MFM-102 PR. |
| GnuCOBOL missing in the session | Devin installs it itself (`apt-get install gnucobol`, ~40 s). Narrate: this is exactly what the blueprint automates. |
| Java build takes too long live | Show the pre-run MFM-101 session (run it the evening before, keep the PR open). The compare output is what matters, not watching Maven download. |
| Jira integration not connected | Move tickets by hand in the browser; Devin's PR comments carry the same evidence. Prompt text is self-contained. |
| `compare.sh` fails during MFM-101 | That *is* the demo: show the diff, let Devin read it and iterate. Byte-compare finding a 1-cent rounding difference is the strongest possible argument for golden-master verification. |
| Network/GitHub hiccup | Local terminal on Eashan's laptop: `scripts/build.sh && scripts/run_job.sh && tests/run_tests.sh` still runs the whole story offline. |

---

## 4. Q&A - the five questions Omkar will ask

**Q1. Indexing limits - can Devin index our entire mainframe estate?**
Index by batch stream / application, not the whole estate. A stream is
typically 50-200 JCL members, the PROCLIB, one copybook library and one
DCLGEN library - well inside a single repository index. Devin's repo search is
semantic and cross-repo, so "where is `.x9` rounding implemented" works across
streams if they are indexed. What does *not* scale is indexing 20 years of
unrelated PDS members: noise, not signal. Practical step: mirror one stream
from Endevor/ChangeMan to git (a one-off Zowe/FTP unload), index it, run this
demo against it.

**Q2. DB2 access - security will not let a tool connect to DB2.**
It does not need to. This demo shows the pattern: DB2 state is an **unload**
(before) and an **unload** (after) taken on the test LPAR by your own DBAs
with your own tooling; Devin only ever sees CSV files. The COBOL is unchanged
in structure - the `EXEC SQL` intent is in the code, DCLGEN copybooks are the
contract, and the compare is byte-for-byte on the unload. When a target does
get real JDBC access later, the same golden files verify it.

**Q3. EBCDIC - our files are EBCDIC, packed decimal, RECFM=FB.**
Encoding is a transport concern, handled at unload time (`iconv`, Zowe, or
the same utility that produces your test-LPAR extracts). The copybook is the
contract; GnuCOBOL can also read EBCDIC directly (`-fdefault-byte`,
`CODE-SET`), and packed decimal (`COMP-3`) is supported natively. This repo
uses ASCII zoned decimal so it runs on any laptop; nothing in the migration
method changes for EBCDIC, only the file-adapter in the target and the
extract step in the pipeline.

**Q4. MQ output - several jobs put messages on MQ for the stores.**
Same golden-master idea, different sink: capture the MQ put payloads on the
test LPAR (or run the COBOL with the MQ layer stubbed to a file, exactly as
the DB2 layer is stubbed here), store them under `data/expected/`, and have
the migrated job write to a file-backed `MessageSink` in test. Byte-compare
the payloads. In production the sink is IBM MQ via JMS; the interface is the
same one `compare.sh` verified.

**Q5. Scale-out - we have hundreds of jobs. How does this become a programme?**
The unit of work is one ticket = one job, driven off a Jira board exactly as
shown, using the two playbooks in `playbooks/`. The estate-wide steps are (a)
an inventory pass (Devin reads every JCL and produces the dependency graph
from `schedules/` + DD datasets - a day for a stream), (b) golden data capture
per job from the test LPAR (your team, scriptable), (c) parallel Devin
sessions per ticket, gated by the byte-compare in CI. Sequencing follows the
scheduler graph: leaf jobs and pure-batch jobs first, DB2-heavy and MQ jobs
after the adapters exist. Human effort concentrates on reviewing specs and
signing off diffs, not on writing Java.
