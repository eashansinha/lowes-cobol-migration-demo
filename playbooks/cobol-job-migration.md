# Playbook: migrate one COBOL/JCL batch job with file parity

Installed in the Devin org as macro `!cobol_job_migrate`. This is the **only**
playbook in the demo. It takes one job from a task file (Markdown today, a Jira
issue once the integration is enabled) to a PR that proves, with a byte-level
file comparison on identical inputs, that the new implementation writes the
same output files as the mainframe job.

Use it once per job. To do many jobs, a parent session runs this playbook in
one child session per job (see "Parallel" at the end).

## Inputs

- `docs/tasks/<JOB>.md` - the task: issue, Ask findings with citations, file
  layouts, reproduction command, verification method, acceptance criteria.
  If given a Jira issue instead, treat its description as this file.
- The repo skill `.agents/skills/mfm-jira-board/SKILL.md` for how to report
  progress (Markdown task file: append a `## Session log` section; Jira: one
  comment per phase, transitions Devin owns only).

## Procedure

1. **Read the task first, code second.** Extract: job name, input DDs, output
   DDs, layouts, the reproduction command, the required proof, and every line
   marked "preserve". If the task file is missing any of these, stop and write
   the question into the task file (or ask once in chat) - do not guess a
   layout or a proof.

2. **Baseline - run the legacy job before writing anything.**
   ```bash
   scripts/build.sh
   scripts/run_<job>.sh            # SORT -> program -> compare against goldens
   tests/run_<job>_tests.sh
   ```
   Record MAXCC, record counts and the comparator verdict. You may not migrate a
   job you cannot run, and you may not proceed if the baseline comparator does
   not PASS on `main`.

3. **Explore from the JCL inward.** `jcl/<JOB>.jcl` -> steps, `COND`, sort
   keys -> each DD -> dataset -> `SELECT ... ASSIGN` -> copybook -> `layouts/`
   JSON. Then the program: validation order, sign handling (`SIGN LEADING
   SEPARATE`, edited pictures), what each total counts, return-code rules.
   Confirm every rule listed in the task file against `file:line`; add any you
   find that the task file missed, under "observed behaviour to preserve".

4. **Implement in a new directory** (`java/<job>/`, Java 17, Maven, Spring
   Batch, no database unless the task says so). Rules:
   - fixed-width writers: pad to LRECL, keep trailing spaces, `\n` line ends
     as in this repo (record the host RECFM/encoding decision in the PR);
   - money as `BigDecimal` with the copybook scale, never `double`;
   - reproduce COBOL truncation / sign / edited-picture behaviour exactly;
   - do **not** touch `cobol/`, `jcl/`, `data/`, `layouts/`, or the goldens.

5. **Run on identical inputs.** Same input files, same `RUNDATE`, output to
   its own directory. Then:
   ```bash
   scripts/compare_<job>.sh <new-output-dir>
   ```
   Layer 1 bytes -> Layer 2 decoded fields -> Layer 3 keyed reconciliation ->
   Layer 4 control totals. Money, counts and keys have zero tolerance.

6. **Explain every difference, then fix it.** For each differing field: which
   rule, which record, legacy value vs new value, root cause in your code.
   Classify as *fixed* (default), *approved deviation* (only if the task file
   says so, with the approver named) or *blocker*. Never edit, re-sort, trim or
   re-encode a baseline to make it match. Repeat 5-6 until exit 0.

7. **Regression harness.** `tests/run_<job>_tests.sh` must still pass
   (proves the COBOL side is untouched). Add the Java run + comparator to CI
   in the same workflow.

8. **PR.** Description contains, pasted from this session's terminal (never
   typed): the comparator tail for every output file, the harness summary, the
   return-code table (sample / clean / empty / bad card), and the rule ->
   class/method mapping. Then update the task file (or Jira) with the PR link
   and leave the human decision - Verified / Done - to a human.

## Stop conditions

- Baseline comparator fails on `main`.
- A layout in the task file disagrees with the copybook.
- An unexplained difference remains after two fix passes.
- The task asks to change behaviour ("while you're in there, fix ...") - that is
  a separate task file and a separate PR.

## Parallel - many jobs at once

A parent session receives a list of task files and starts one child session
per job with:

```
Follow playbooks/cobol-job-migration.md for docs/tasks/<JOB>.md. Report back
the PR URL, the comparator verdict per output file and any stop condition hit.
```

The parent only collects results and never merges: each PR is reviewed with
Devin Review and approved by a human who owns that job.

## Verification of the deliverable

This estate is batch only - there is no web frontend to open, so the proof is
the layered file comparison on identical inputs plus the regression harness,
pasted verbatim into the PR. If a job in scope ever gains a UI (an operator
console, a report viewer), the same rule applies in its shape: start it, walk
its main pages before and after the change, and attach a screen recording as
the evidence instead of describing it.
