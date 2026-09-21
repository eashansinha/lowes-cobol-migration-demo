---
name: cobol-ask
description: Read-only "ask mode" for a COBOL/JCL question or a Jira ticket in this repo. Answer with file:line citations and a scoped plan; never edit, build, open a PR or move the ticket. Use when a Jira comment or ticket asks a question, carries the !cobol_ask label, or the task says explore/scope/explain.
allowed-tools: Read, Grep, ListDir
argument-hint: <question or MFM ticket key>
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
6. **If asked to scope** - a plan of <=10 steps mapped onto the repo's loop
   (baseline `scripts/build.sh && scripts/run_job.sh && scripts/compare.sh`
   -> explore -> spec -> plan -> implement -> compare on the same inputs -> CI
   gate -> PR), the golden files that would change, and a confidence
   estimate: high / medium / low with one sentence why.

Finish with: "To implement, start a Devin session with `!jcl_migrate` or
`!cobol_fix` on this ticket." Do not start it yourself.
