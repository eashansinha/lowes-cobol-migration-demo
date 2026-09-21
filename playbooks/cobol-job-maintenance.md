# Playbook: in-place COBOL change with regression proof

Installed in the Devin org as macro `!cobol_fix` (usable as a Jira playbook label).

Use for tickets that change the behaviour of an existing COBOL program that
stays in production (defect fix, rule change, new field). The deliverable is
a PR that shows **exactly** which outputs change, proves everything else is
unchanged, and leaves the golden files describing the new behaviour.

## Procedure

1. **Claim the ticket.** Move it to *In Progress*, comment the session link.
   Extract from the ticket: program, paragraph, the defect/rule change, and
   the expected output changes. If the ticket does not state expected values,
   derive them from the rule text and write them down *before* coding.

2. **Prove the current behaviour first.** Build and run on `main`:
   ```bash
   scripts/build.sh && scripts/run_job.sh && tests/run_tests.sh
   ```
   Quote the report lines / CSV rows / test assertions that show the current
   (defective) behaviour in your notes and later in the PR. If you cannot
   reproduce the defect with the sample data, add a data case that does
   (and regenerate the goldens from the *unchanged* program so the new case
   documents current behaviour), then continue.

3. **Understand the blast radius.** Read the paragraph named in the ticket
   and every paragraph it `PERFORM`s or is performed from. List other paths
   that reach the same helpers (e.g. rounding helpers used by both standard
   and clearance pricing) - those must not change. Check callers of any
   changed copybook.

4. **Make the minimal change.** Touch only the paragraph(s) the ticket names.
   Keep the COBOL style of the file (column-7 comments, paragraph numbering,
   no new `GO TO`). Do not refactor neighbours; do not "fix" other things you
   notice - open a new ticket for them.

5. **Regenerate and inspect the goldens deliberately.**
   ```bash
   scripts/build.sh && scripts/run_job.sh --no-compare
   diff data/expected/PRCUPD01.rpt work/PRCUPD01.rpt
   diff data/db2/expected_after/ITEM_PRICE.csv work/ITEM_PRICE.csv
   diff data/db2/expected_after/PRICE_HIST.csv work/PRICE_HIST.csv
   ```
   Every changed line must be explained by the ticket. Anything else is a
   regression - stop and fix the code, not the golden. Only then copy the
   `work/` outputs over the golden files.

6. **Update and extend the tests.** Change the assertions that encoded the
   old behaviour, and add at least one assertion for the *class* of defect
   (e.g. "no floored row is below its floor"), not just the single row.
   Run `tests/run_tests.sh`; all must pass. Run `scripts/run_job.sh` once more
   and confirm MAXCC is what the ticket expects and `compare.sh` passes.

7. **Deliver.** PR against `main` with: the defect in one sentence, the
   before/after excerpt from step 2 vs step 5, the `git diff --stat` on
   `data/` (should be only the expected files), and the test summary line.
   Move the ticket to *In Review* with PR + session links.

## Done when

- Only the named paragraph(s) changed in COBOL.
- Golden files differ from `main` in exactly the lines the ticket predicts.
- New regression assertion added; `tests/run_tests.sh` green; CI green.
- Ticket in *In Review* with before/after evidence.

## Verification of the deliverable

No frontend exists for this estate; proof is the report/CSV diffs plus the
test harness. Include them in the PR verbatim rather than describing them.
