---
name: cobol-ask
description: Read-only "ask mode" for a COBOL/JCL question in this repo (Ask Devin / DeepWiki, or a Jira comment once the integration is enabled). Answer with file:line citations; when asked to plan, produce a docs/tasks/<JOB>.md-shaped task ending with the Devin prompt. Never edit, build, open a PR or move a ticket. Use when the request says explain / explore / scope / plan.
allowed-tools: Read, Grep, ListDir
argument-hint: <question or job name>
---

# COBOL ask mode (no side effects)

You are answering, not implementing. No edits, no shell, no PR, no Jira
transitions. Follow `mfm-jira-board` for reading the ticket; skip its
transition steps.

## Answer shape

Start from the JCL and walk outward; cite everything.

1. **Job** - `jcl/<JOB>.jcl`: each STEP, its PGM, COND/IF, and each DD name.
2. **Program** - `cobol/src/<PGM>.cbl`: SELECT/ASSIGN for each DD, the
   copybook each FD uses (`cobol/copybooks/`), the paragraphs on the path the
   question is about (`file:line` or paragraph name), CALLs and EXEC SQL /
   DCLGEN -> `cobol/sql/ddl/`.
3. **Data** - which `data/input/*`, `data/db2/before/*.csv` and
   `data/expected/*` / `data/db2/expected_after/*.csv` are touched.
4. **Downstream** - jobs in `schedules/nightly.txt` that consume the outputs
   (STEP order and scheduler conditions are dependencies; a shared dataset
   name alone is only a candidate).
5. **Findings** - behaviour that looks like a defect, an implicit assumption
   (truncation vs ROUNDED, sign handling, COMP-3 widths, sort order), or an
   unresolved question. Label each "observed - preserve unless a ticket says
   fix".
6. **If asked to plan / scope** - write the task in the shape of
   `docs/tasks/GLPOST01.md`: issue, findings with citations, input/output
   files with layouts, the reproduction command (`scripts/build.sh &&
   scripts/run_<job>.sh`), how parity is verified (bytes -> decoded fields ->
   keyed reconciliation -> control totals, zero tolerance on money, counts,
   keys), acceptance criteria, blockers, and finish with the exact prompt for
   the Devin session (pointing at the task file and
   `playbooks/cobol-job-migration.md`). Same text is what goes into Jira.

Do not start the implementation session yourself.
