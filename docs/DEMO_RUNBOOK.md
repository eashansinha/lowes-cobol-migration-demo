# Demo runbook - one COBOL job, file in -> file out, end to end

Audience: Lowe's finance / mainframe team (Renuka's group). No slides.
One story, one job, ~25 minutes. Every prompt below is copy-paste.

**The story in one line:** *the mainframe job reads two files and writes
three; the new job must write the same three bytes-for-bytes from the same
two - and Devin does the work while the finance team keeps every decision.*

Job: `GLPOST01` - daily general-ledger posting.
`GLTRANS.dat` (journal feed) + `ACCTMAST.dat` (chart of accounts)
-> `GLPOSTED.dat` (posted ledger) + `GLEXCEPT.dat` (rejects) + `GLPOST01.rpt` (batch control report).

## Before you start

- Repo `eashansinha/lowes-cobol-migration-demo` indexed in the org; DeepWiki built.
- Two browser tabs side by side: **Ask Devin** (left) and **Sessions** (right).
- Terminal in the repo with `scripts/build.sh && scripts/run_glpost01.sh`
  already run once (shows `MAXCC=4`, `compare_glpost01.sh: PASS`).
- Optional pre-start (saves 10 min): a session already running the Step 4
  prompt so its PR exists when you reach Step 5.

## Agenda

| # | Step | Min | What is on screen |
|---|---|---|---|
| 1 | Ask Devin + DeepWiki: understand the job | 5 | Ask tab, answers with `file:line` |
| 2 | Ask plan mode -> Markdown task (Jira later) | 4 | `docs/tasks/GLPOST01.md` |
| 3 | Construct the Devin prompt | 1 | last block of the task file |
| 4 | Devin session: baseline, migrate, prove parity | 8 | session terminal, comparator output |
| 5 | Devin Review + free chat on the PR | 4 | PR with review comments |
| 6 | One playbook -> parallel child sessions | 3 | parent session spawning children |

---

## Step 1 - Ask Devin + DeepWiki (5 min)

**Say:** "Before anyone writes code we need to know what the job actually does.
Not what the 2012 design doc says - what the JCL and COBOL do today."

**Do:** in the Ask tab, repo `lowes-cobol-migration-demo`, send:

```
Walk me through jcl/GLPOST01.jcl: every step, its PGM and COND, the sort key,
and every DD name mapped to the COBOL SELECT/ASSIGN and its copybook. Which
files are inputs, which are outputs, and what are their RECFM/LRECL?
```

**Show:** the three steps, the SORT key (BATCH-ID / ACCT-NO / TRAN-ID), the
DD -> copybook table, 100/60 in, 120/80/132 out. Point at the `file:line`
citations - "every claim is clickable."

**Then send:**

```
List the business rules in cobol/src/GLPOST01.cbl with paragraph and line
references: validation order and exception codes, how the signed amount on
GLPOSTED is derived, what the batch debit/credit totals include, and every
return-code condition. Flag anything that looks like a defect but should be
preserved in a migration.
```

**Show:** BR-V1..V7 in order (first failure wins), BR-P1 sign rule, and the
finding: *an E004 line counts in neither batch total, so MAN09211 shows OUT OF
BALANCE.* **Say:** "Devin found that; whether it is a bug or a control is a
finance decision - it gets written down as *preserve*, not silently changed."

Leave the Ask tab open. Any question from the room goes there, not into the
session.

## Step 2 - Ask plan mode -> Markdown task (4 min)

**Say:** "Now we turn that understanding into a ticket. Lowe's Jira isn't
connected to Devin yet, so the ticket is a Markdown file in the repo. The day
Jira is connected, the same text goes into the issue and nothing else changes."

**Do:** same Ask conversation, send:

```
Turn this into a migration task for GLPOST01 -> Java Spring Batch. Include:
the issue, your findings with citations, the input/output files with layouts,
the command to reproduce the legacy run, how parity will be verified (bytes,
decoded fields, keyed reconciliation, control totals - zero tolerance on
money, counts and keys), acceptance criteria, and what counts as a blocker.
Finish with the exact prompt I should give a Devin session to do the work.
```

**Show:** the answer next to the committed exemplar `docs/tasks/GLPOST01.md`
(same structure). Scroll to **Acceptance criteria** and **Blockers**: "the
COBOL, the JCL and the golden files are untouched; any unexplained byte
difference stops the work."

**Say:** "This file is also the audit trail. The session appends a log to it
as it works."

## Step 3 - Construct the Devin prompt (1 min)

**Show:** the last block of `docs/tasks/GLPOST01.md`:

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

**Say:** "Three things make this a good prompt: it points at the task file,
it points at the playbook, and it says how 'done' is proved. Nothing about
*how* to write Java."

## Step 4 - Devin session (8 min)

**Do:** Sessions tab -> New session -> paste the prompt. (Or switch to the
pre-started session.)

**Show, in order, narrating each:**

1. **Baseline first.** Terminal: `scripts/build.sh` (GnuCOBOL compile),
   `scripts/run_glpost01.sh` -> `READ=31 POSTED=22 REJECTED=9 RC=04`,
   `compare_glpost01.sh: PASS`. **Say:** "Devin may not migrate a job it
   cannot run. This is the mainframe truth it has to match."
2. **Explore from the JCL inward** - it reads the copybooks and
   `layouts/*.json` before the program.
3. **Implement** under `java/glpost01/` - nothing under `cobol/`, `jcl/`,
   `data/`, `layouts/` changes (show `git status`).
4. **Same inputs, new outputs, compare:**
   ```
   scripts/compare_glpost01.sh java/glpost01/target/out
   ```
   **Say what the four layers are while it scrolls:** bytes -> which field
   differs, decoded -> which TRAN-ID is missing/changed -> control totals.
   "Money, counts and keys have zero tolerance. A checksum match proves
   equality; a mismatch starts an investigation, never a judgement call."
5. If a first pass differs (it usually does on sign or padding): show the
   Layer 2 line - e.g. `key T000000409  DESCRIPTION  NO DESCRIPTION -> ` -
   then the fix, then the re-run to `IDENTICAL`.
6. **Regression harness** `tests/run_glpost01_tests.sh` -> `56 passed`.
7. **PR opened**, description carries the pasted comparator tail.

**Fallback if the session is slow:** run the comparator yourself against a
deliberately broken copy to show the layers:
```
sed -e '/T000000406/d' work-glpost01/GLPOSTED.dat > /tmp/GLPOSTED.dat
scripts/compare_files.py --layout layouts/GLPOSTED.json \
  --baseline data/expected/GLPOST01/GLPOSTED.dat --target /tmp/GLPOSTED.dat
```
-> Layer 3 `missing : T000000406`, Layer 4 `sum SIGNED-AMT 232127.73 vs 232872.98 DIFFERS`, exit 8.

## Step 5 - Devin Review + free chat (4 min)

**Do:** open the PR. Devin Review runs on every PR automatically.

**Show:** the review comments - Review reads the diff against the copybooks
and the task file, so findings look like "BigDecimal scale lost on
SIGNED-AMT" or "writer trims trailing spaces". **Say:** "Review catches
Devin's own mistakes - independent eyes on the code, before a human spends time."

**Do:** in the PR chat / session, ask a free-form question:

```
Show me where BR-P1 (signed amount by normal balance) is implemented in the
Java and the COBOL side by side, and the test that pins it.
```

**Say:** "Approval stays human. The finance owner reads the comparator tail,
reads the review, and decides. Devin never marks anything Verified or Done."

## Step 6 - One playbook, many jobs (3 min)

**Say:** "Everything you just saw is one playbook -
`playbooks/cobol-job-migration.md`. It is the only one we need. Scaling is
not a different process; it is the same process run in parallel."

**Do:** new session:

```
For each task file in docs/tasks/, start one child session that follows
playbooks/cobol-job-migration.md for that job. Do not merge anything. Report
back a table: job, PR URL, comparator verdict per output file, stop
conditions hit.
```

**Show:** the parent spawning a child per task file. **Say:** "Fifty jobs is
fifty task files. Each PR still gets Devin Review and a human owner."

## Close

Ask: "Which real job's input and output files could we get a one-day sample
of?" - that is the next step, and it needs nothing but two files and the
copybooks.

## Points to land (say each at least once)

1. Baseline first - Devin runs the mainframe job before writing a line.
2. Parity means bytes on the same input, not "tests pass".
3. Every difference is explained and classified; unexplained = blocker.
4. Findings are recorded as *preserve*, humans decide whether to change them.
5. Markdown task today, Jira ticket tomorrow - same content, same loop.
6. One playbook; scale is parallel children, not a new process.
