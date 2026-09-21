# Demo guide: Jira ticket -> Devin session -> verified PR

> **Status (2026-09-21):** the live demo now runs from a Markdown task file
> (`docs/tasks/GLPOST01.md`) with **one** org playbook, `!cobol_job_migrate`
> (`playbooks/cobol-job-migration.md`); see `DEMO_RUNBOOK.md`. Jira is the
> *later* task source, and this guide is kept as the reference for that path.
> The `!jcl_migrate`, `!cobol_fix` and `!cobol_ask` macros it used to name
> have been removed from the Devin org: migration work uses
> `!cobol_job_migrate`; ask mode is Ask Devin / DeepWiki with the repo skill
> `.agents/skills/cobol-ask/SKILL.md` (no macro); in-place fixes such as
> MFM-2 / MFM-10 have no playbook and are worked in a plain session that
> follows `.agents/skills/mfm-jira-board/SKILL.md` from a task file.

Companion to `DEMO_RUNBOOK.md` (minute-by-minute) and `JIRA_SETUP.md` (board and
ticket text). This guide answers three questions Omkar asked for on 2026-09-18:

1. How does a Jira ticket become a Devin session (and how do I do it by hand
   from Ask Devin when I do not want the integration to fire)?
2. How is the Lowe's mainframe estate replicated so the demo is honest about
   JCLs, schedules, inter-job dependencies and DB2?
3. How do I make sure Devin runs the **full verification loop** and cannot
   declare success without a diff?

Everything below is set up in the Eashan-Dev Devin org against
`eashansinha/lowes-cobol-migration-demo`.

Live sandbox (cog-gtm Jira, project `MFM`, board
https://cog-gtm.atlassian.net/jira/software/projects/MFM/boards/2594):

| Docs alias | Live key | URL |
|------------|----------|-----|
| MFM-101 migrate `PRCUPD01` to Java | `MFM-1` | https://cog-gtm.atlassian.net/browse/MFM-1 |
| MFM-102 fix clearance floor rounding | `MFM-2` | https://cog-gtm.atlassian.net/browse/MFM-2 |

---

## 1. Three ways a ticket becomes a session

Use path B for the live demo (most control), mention A and C as "what your
engineers will actually do day to day".

### A. Jira integration (hands-off)

Requires Jira connected in *Settings -> Connections -> Jira* of the Devin org
and the playbook added as a **playbook label** (`!cobol_job_migrate`; create
the same-named label in the MFM project).
Every trigger below *starts a session*; what that session is allowed to do is
decided by the playbook it lands on, and whether it starts at all by the
integration's **Session mode**:

| Trigger in Jira | What Devin uses |
|-----------------|-----------------|
| Comment `@Devin <question>` (ask mode) | a session that follows the repo skill `cobol-ask`: read-only analysis, answer + task-file-shaped plan as a Jira comment, no code, no PR, no transition |
| Add label `!cobol_job_migrate` | the migration playbook, full implementation session |
| Assign the ticket to the Devin user / add label `devin` | default playbook (leave unset, or `!cobol_job_migrate` for a migration-only board) |
| Comment `@Devin <instruction>` | the comment as the task, no playbook |
| Automation trigger: project `MFM`, status `Ready for Devin` | configured playbook (not yet verified on the sandbox, see below) |

**Ask mode, two ways to get it**

1. *Repo skill `cobol-ask`* (what we demo, from Ask Devin / DeepWiki). It is
   read-only - no edits, builds, PRs or Jira transitions - and tells Devin to
   answer with `file:line` citations, list observed defects as "preserve",
   and when asked to plan produce a `docs/tasks/<JOB>.md`-shaped task that
   ends with the Devin prompt. Because it is a repo skill it applies in any
   session on the repo, including one started from a Jira comment. Costs one
   short session; `!cobol_job_migrate` on another ticket still runs as a
   full session.
2. *Session mode = Scoping only* (integration setting). Devin then never
   starts a session from Jira: every trigger yields a scoping comment
   (summary, implementation plan, confidence estimate) and a link you click
   to start the real session yourself. Org-wide toggle - it turns off
   hands-off implementation for every project, so use it for a customer that
   wants humans to approve every session, not for the demo.

Plain `@Devin how does X work?` is *not* ask mode by itself: without a
playbook it starts a full session with the comment as the task (though a
question-shaped task usually stays read-only). Say "ask mode" / "explain" /
"plan" so the `cobol-ask` skill applies, and never say "implement".

In full sessions Devin posts the session link back as a Jira comment, moves
the ticket to `In Progress`, and when the PR opens it adds the PR as a remote
link plus a comment with the verification summary. Follow-ups are `@Devin`
comments on the ticket; they route to the existing session.

Verified on the cog-gtm sandbox (2026-09-21): creating an MFM ticket **with the
`devin` label** starts a session in the Eashan-Dev org within seconds and links
it back on the ticket (MFM-9, MFM-14). Creating a ticket without the label, or
re-adding the label to an existing ticket that already has a session, does not.
The `devin`-labelled tickets are the ones you want Devin to work; keep the
label off pure context/history tickets.

For the board in `JIRA_SETUP.md` the automation trigger to configure is:
*project = MFM, status = Ready for Devin, playbook = `!cobol_job_migrate`*
(migration stories only; bugs have no playbook and are started by hand). The
automation has not been exercised on the sandbox yet (the `devin` label is the
only trigger verified above), so do not rely on a status move to start a
session during the demo unless you have tested it first; use the label or
path B instead.

**Why every session knows about the board.** Two always-on pieces of
context, no prompt needed:

- Repo skill `.agents/skills/mfm-jira-board/SKILL.md` - board URL, live
  ticket keys, the phase-comment format (`BASELINE / EXPLORE / IMPLEMENT /
  PARITY / VERIFY`), the transitions Devin owns (`Ready for Devin -> In
  Progress -> In Review`) and the ones it never touches (`Verified`, `Done`).
  Devin discovers `SKILL.md` files from the index at session start and again
  from disk once the repo is cloned.
- Org knowledge note *"MFM Jira board protocol"* pinned to the repo in the
  Devin org - a short pointer to the same rules so they are present before the
  clone finishes and in Ask Devin.

The playbook (`!cobol_job_migrate`) opens with "read the task file and
follow `mfm-jira-board`", so the board is read at the start, written at every
phase, and the ticket lands in `In Review` with the evidence attached.

### B. Ask Devin / new session from the ticket (what we drive live)

1. Open the ticket in Jira, copy its URL.
2. In Devin, start a new session on the repo `eashansinha/lowes-cobol-migration-demo`
   and paste, filling in the ticket URL and the playbook (`!cobol_job_migrate`
   for migration Stories; for Bugs omit the playbook sentence - there is none):

   ```
   Work Jira ticket <TICKET_URL>. Read the ticket and its comments first,
   then follow the playbook <PLAYBOOK>. Post a short comment on the ticket
   at the end of each phase (baseline / explore / implement / parity / verify)
   and move it to In Progress now and In Review when the PR is open.
   ```

   Filled in for the two tickets used in this demo:

   - MFM-1 (MFM-101, migration Story):
     `Work Jira ticket https://cog-gtm.atlassian.net/browse/MFM-1 ... follow the playbook !cobol_job_migrate ...`
   - MFM-10 (WC lumber cap Bug, the fresh pick-up):
     `Work Jira ticket https://cog-gtm.atlassian.net/browse/MFM-10 ... follow .agents/skills/mfm-jira-board/SKILL.md; no playbook ...`

   Devin reads the ticket through the Jira connection (or, if Jira is not
   connected, use Prompt A / Prompt B from `DEMO_RUNBOOK.md` which contain the
   full ticket text). The repo blueprint gives it GnuCOBOL and the build; the
   pinned knowledge note gives it the verification rules in section 3.
3. Narrate what arrives in the session: the ticket text, the playbook, the
   knowledge note, the indexed repo. This is the "context engineering" slide
   from the planning call, shown live instead of described.

Ask Devin (read-only Q&A, no session) is the right tool for the exploration
questions while a session runs, e.g. *"which downstream jobs read
ITEM_PRICE?"* - it answers from the index with citations. Caveat to state:
Ask Devin only searches the repos ticked in the selector (currently the last
20 indexed), so engineers must tick the right estate repo(s).

### C. API (for a board-driven pipeline at scale)

`POST https://api.devin.ai/v3/organizations/{org_id}/sessions` with the ticket
key in the prompt and `playbook_id` set to the batch-migration playbook. This
is how a Jira automation or a scheduler creates one session per job for a
whole batch stream; the organisation-level playbooks, knowledge and blueprint
apply automatically. Repos are indexed the same way:
`PUT /v3beta1/organizations/{org_id}/repositories/{owner%2Frepo}/indexing`.

---

## 2. Replicating the Lowe's estate (what the repo mirrors and why)

Omkar's repo has JCLs, scheduler tables, job interdependencies and extracted
DB2 schemas; direct DB2 is blocked by security. The demo repo mirrors each of
those so the pattern transfers 1:1:

| Lowe's artefact | In this repo | Devin uses it for |
|-----------------|--------------|-------------------|
| JCL members | `jcl/PRCUPD01.jcl`, `jcl/INVREPL01.jcl` (STEP010 SORT -> STEP020 program -> STEP030 compare, DD names, COND) | entry point of every explore; DD -> file -> copybook mapping; return-code semantics |
| Scheduler table | `schedules/nightly.txt` (INVREPL01 depends on PRCUPD01) | dependency edges come only from scheduler facts + step order, never from "shared dataset name" |
| Programs and subprograms | `cobol/src/PRCUPD01.cbl`, `CALL 'PRCRGN01'` | call graph, paragraph flow, business rules with BR ids |
| Copybooks / DCLGEN | `cobol/copybooks/*.cpy` (record layouts and `DCL*` host-variable copybooks) | record contracts; numeric PIC/COMP-3 semantics |
| DB2 schema | `cobol/sql/ddl/*.sql` | table contract for the Java repositories |
| DB2 data | `data/db2/before/*.csv` (unload before the job), `data/db2/expected_after/*.csv` (unload after) | the oracle - no DB2 connection needed, DBAs produce the unloads |
| Input feeds | `data/input/*.dat`, `STORE_REGION.csv` | identical inputs for COBOL and Java |
| Audit report | `data/expected/PRCUPD01.rpt` | byte-compared output |

Things to say out loud, because they are the questions security and the
mainframe team will ask:

- **No credentials anywhere.** Devin never touches DB2, MQ or the LPAR. Your
  own tooling produces unloads on the test LPAR; Devin sees files.
- **Data handling.** Unloads used as fixtures must be masked/tokenised and
  kept in a repo with the same access controls as the source. Retention and
  sign-off belong to the ticket's acceptance criteria.
- **Encoding.** This repo is ASCII line-sequential so it runs on a laptop.
  EBCDIC/RECFM=FB/COMP-3 are handled at unload time or by a byte-record reader
  in the Java target; the copybook stays the contract. Do not let anyone claim
  a plain text-line reader preserves mainframe semantics.
- **Scale.** Index by batch stream (50-200 JCL members + PROCLIB + copybook
  library + DCLGEN library), not the whole PDS estate.

Environment as configured in Eashan-Dev (mirror this for Lowe's):

| Item | Eashan-Dev state |
|------|------------------|
| Repo indexed | `eashansinha/lowes-cobol-migration-demo` (main) |
| Repo blueprint | installs GnuCOBOL, runs `scripts/build.sh`, knowledge entries for build/test/verify/DB2 |
| Knowledge note | "Lowe's COBOL demo repo: verification loop and working rules", pinned to the repo |
| Playbooks | `!cobol_job_migrate` (batch migration, the only one in the demo); `!cobol_to_springboot` (CICS/online, separate demo) |
| Secrets | none required |
| Jira | Atlassian connection must be (re)authorised by Eashan; project `MFM`, board per `JIRA_SETUP.md` |

---

## 3. The full verification loop (what Devin must do, in order)

The loop is oracle-first: the existing COBOL run defines truth *before* any
new code exists. It is encoded three times so Devin cannot skip it - in the
playbooks, in the pinned knowledge note, and in CI.

```
 0. Claim ticket -> In Progress; read ticket, comments, linked spec.
 1. ORACLE     scripts/build.sh && scripts/run_job.sh && scripts/compare.sh
               expect: build OK, MAXCC=4, compare PASS.  Save MAXCC, report,
               after-state CSVs, reject counts, control totals.
 2. EXPLORE    from the JCL outward: DD names -> SELECT/ASSIGN -> copybooks;
               STEP order + COND; CALLs; EXEC SQL / DCLGEN -> DDL; schedule.
 3. SPECIFY    docs/specs/<JOB>.md from MIGRATION_SPEC_TEMPLATE.md; every
               rule cites file:line / paragraph; observed defects are
               recorded as "preserve" unless the ticket says fix.
               Anything unresolved is written down as a finding, not guessed.
 4. PLAN       target layout (Spring Batch steps / reader / processor /
               writer, or the COBOL paragraph change).  Human OK here.
 5. IMPLEMENT  pass 1 structure-preserving; BigDecimal with explicit
               COBOL truncation / ROUNDED / SIZE ERROR semantics; same
               MAXCC conventions.  Refactor (pass 2) only after pass 1 passes.
 6. VERIFY     run candidate on the SAME inputs; scripts/compare.sh on the
               candidate output dir: report bytes, each DB2 after-state
               table, row counts, control totals, return code.
               Every difference is explained in the PR or blocks the PR.
 7. GATE       parity command added to .github/workflows/ci.yml.
 8. EVIDENCE   PR body + Jira comment carry: compare output, MAXCC,
               before/after diff of any golden file the ticket allowed to change.
 9. STATUS     -> In Review.  Humans move In Review -> Verified -> Done.
```

What "passes" looks like for the two demo tickets:

| Ticket | Golden files | compare.sh | Report diff | DB2 diff |
|--------|--------------|------------|-------------|----------|
| MFM-101 migrate | unchanged | exit 0 on the Java output | empty | empty |
| MFM-102 fix BR-P6 | 3 files updated, diff shown in PR | exit 0 after update | exactly 4 detail lines `272.99 -> 273.09`, totals identical | 4 `ITEM_PRICE` rows, 4 `PRICE_HIST` rows |

Hardening points to raise if Omkar asks "how do we trust this on real jobs"
(from the internal playbook review):

- Copybook layout is derived by the compiler-grade reader, not a regex:
  `COMP`, `COMP-3`, separate signs, edited pictures, `PIC A`, group `OCCURS`.
- Scheduler edges only from JCL step order and scheduler conditions; a
  shared dataset name is a *candidate*, not an edge.
- Business date, restart/idempotency and `COND`/`IF` step skipping are part
  of the spec, not an afterthought.
- Two-pass translation: parity tests from pass 1 are the regression suite
  for the idiomatic pass 2.
- Same pattern for other sinks: file output (this demo), DB2 update (this
  demo via unloads), MQ (capture puts to a file, compare payload bytes).

---

## 4. Ticket lifecycle Devin follows

```
Backlog -> Ready for Devin -> In Progress -> In Review -> Verified -> Done
            (human)          (Devin, on     (Devin, when   (human, after   (human,
                              session start) PR + evidence) re-running      on merge)
                                                            compare.sh)
```

Devin never moves a ticket to `Done`. While a PR is open the ticket stays in
`In Review` with the reason in the latest comment.

---

## 5. Pre-flight checklist (15 minutes before)

- [x] PR #1 merged to `main`, so the estate is on the indexed branch.
- [x] Atlassian connection authorised in Eashan-Dev; project `MFM` exists.
      MFM-1 / MFM-2 (aliases MFM-101 / MFM-102) are in `In Progress` with
      sessions already attached; to show the pick-up moment live, use a ticket
      with no existing session, such as MFM-10 (no playbook; plain session).
      Fallback: use Prompt A / Prompt B from `DEMO_RUNBOOK.md`.
- [x] Routing to Eashan-Dev verified via MFM-9 / MFM-14 (see section 1A).
- [ ] Jira integration: `!cobol_job_migrate` added as a playbook label (optional;
      the runbook does not depend on it).
- [ ] Warm-up session on the repo: *"Run tests/run_tests.sh and report MAXCC
      and pass count"* -> MAXCC=4, 48 passed. Confirms snapshot + GnuCOBOL.
- [ ] Optional pre-run of MFM-101 (Java build takes minutes) kept open as a
      fallback session.
- [ ] Browser tabs: Jira board, Devin org (repo, playbooks, knowledge),
      GitHub PR list.

Timeline: 30-minute smoke test with Omkar today; the 15-minute engineer-facing
cut is sections 1B, 3 and the MFM-102 PR only.
